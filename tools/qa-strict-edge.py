#!/usr/bin/env python3
"""Build deterministic fixed-crop QA evidence for a strict-endpoint edge job."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ACTIONS = ROOT / "workspaces/wubai-private/actions"
BASE = ACTIONS / "side-curled-left-to-sit-front/v1/qa/process_candidate.py"
SPEC = importlib.util.spec_from_file_location("petsgraph_strict_edge_qa_base", BASE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Cannot load QA helpers: {BASE}")
base = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(base)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def resolve(path: str) -> Path:
    candidate = Path(path)
    return candidate if candidate.is_absolute() else ROOT / candidate


def embed(frame: Image.Image, size: tuple[int, int], offset: tuple[int, int]) -> Image.Image:
    if frame.size == size and offset == (0, 0):
        return frame
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.alpha_composite(frame.convert("RGBA"), offset)
    return canvas


def prepare_reference(
    frame: Image.Image,
    size: tuple[int, int],
    crop: tuple[int, int, int, int] | None,
    offset: tuple[int, int],
) -> Image.Image:
    prepared = frame.convert("RGBA")
    if crop is not None:
        prepared = prepared.crop(crop)
    return embed(prepared, size, offset)


def review_canvas(frame: Image.Image) -> Image.Image:
    if frame.size == (640, 640):
        return frame
    scale = min(640 / frame.width, 640 / frame.height)
    resized = frame.resize(
        (round(frame.width * scale), round(frame.height * scale)), Image.Resampling.LANCZOS
    )
    canvas = Image.new("RGBA", (640, 640), (0, 0, 0, 0))
    canvas.alpha_composite(resized, ((640 - resized.width) // 2, (640 - resized.height) // 2))
    return canvas


def metrics(frame: Image.Image, source_index: int) -> dict[str, object]:
    alpha = np.asarray(frame)[..., 3]
    ys, xs = np.where(alpha > 12)
    if not len(xs):
        raise RuntimeError(f"No foreground in frame {source_index}")
    left, top, right, bottom = int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())
    width, height = frame.size
    outer_by_side = {
        "left": int(alpha[:, :8].max()),
        "right": int(alpha[:, -8:].max()),
        "top": int(alpha[:8, :].max()),
        "bottom": int(alpha[-8:, :].max()),
    }
    return {
        "sourceIndexZeroBased": source_index,
        "bboxInclusive": [left, top, right, bottom],
        "margins": {
            "left": left,
            "right": width - 1 - right,
            "top": top,
            "bottom": height - 1 - bottom,
        },
        "center": [(left + right) / 2, (top + bottom) / 2],
        "visibleArea": int(np.count_nonzero(alpha > 12)),
        "outerEightPixelAlphaMax": max(outer_by_side.values()),
        "outerEightPixelAlphaMaxBySide": outer_by_side,
    }


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: qa-strict-edge.py <job-directory>")
    job = resolve(sys.argv[1])
    qa = job / "qa"
    # The imported helper keeps its own module-level QA path. Redirect it so
    # generated previews stay with this job instead of contaminating the base
    # side-curled candidate directory.
    base.QA = qa
    config = json.loads((job / "qa-config.json").read_text(encoding="utf-8"))
    request = json.loads((job / "request-config.json").read_text(encoding="utf-8"))
    fps = int(config.get("fps", 24))
    expected = int(request["durationSeconds"]) * fps + 1
    crop = tuple(int(value) for value in config.get("cropBoxInclusiveExclusive", [160, 160, 800, 800]))
    compiled_size = (crop[2] - crop[0], crop[3] - crop[1])
    endpoint_offset = tuple(int(value) for value in config.get("endpointEmbedOffset", [0, 0]))
    source = job / "artifacts" / f"{request['artifactStem']}.mp4"
    raw = qa / "raw-frames"
    transparent_safe = qa / "transparent-safe960-frames"
    compiled = qa / "compiled-fixed-crop640-frames"
    for directory in (raw, transparent_safe, compiled):
        directory.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(source),
            "-vsync", "0", str(raw / "frame-%03d.png"),
        ],
        check=True,
    )
    raw_paths = sorted(raw.glob("frame-*.png"))
    if len(raw_paths) != expected:
        raise RuntimeError(f"Expected {expected} frames, found {len(raw_paths)}")

    frames: list[Image.Image] = []
    frame_metrics: list[dict[str, object]] = []
    for index, path in enumerate(raw_paths):
        full = base.key_cyan(Image.open(path))
        full.save(transparent_safe / f"frame-{index:03d}.png", optimize=True)
        frame = full.crop(crop)
        frame.save(compiled / f"frame-{index:03d}.png", optimize=True)
        frames.append(frame)
        frame_metrics.append(metrics(frame, index))

    endpoint_crop_value = config.get("endpointCropBoxInclusiveExclusive")
    endpoint_crop = (
        tuple(int(value) for value in endpoint_crop_value)
        if endpoint_crop_value is not None
        else None
    )
    source_endpoint = prepare_reference(
        base.key_cyan(Image.open(resolve(config["sourceEndpointPath"]))),
        compiled_size,
        endpoint_crop,
        endpoint_offset,
    )
    target_endpoint = prepare_reference(
        base.key_cyan(Image.open(resolve(config["targetEndpointPath"]))),
        compiled_size,
        endpoint_crop,
        endpoint_offset,
    )
    target_loop_path = resolve(config["targetLoopPath"])
    target_loop_crop_value = config.get("targetLoopCropBoxInclusiveExclusive")
    target_loop_crop = (
        tuple(int(value) for value in target_loop_crop_value)
        if target_loop_crop_value is not None
        else None
    )
    target_loop_offset = tuple(
        int(value) for value in config.get("targetLoopEmbedOffset", endpoint_offset)
    )
    target_loop = [
        prepare_reference(
            Image.open(path), compiled_size, target_loop_crop, target_loop_offset
        )
        for path in sorted(target_loop_path.glob("frame-*.png"))
    ]
    expected_loop = int(config["targetLoopExpectedFrames"])
    if len(target_loop) != expected_loop:
        raise RuntimeError(f"Expected {expected_loop} target-loop frames, found {len(target_loop)}")

    chain: list[tuple[Image.Image, str]] = []
    chain.extend((review_canvas(source_endpoint), f"source hold {index + 1}/{fps}") for index in range(fps))
    chain.extend((review_canvas(frame), f"edge source {index}") for index, frame in enumerate(frames))
    chain.extend((review_canvas(frame), f"target loop runtime {index}") for index, frame in enumerate(target_loop))

    indexes = sorted(set(list(range(0, expected, 4)) + [expected - 2, expected - 1]))
    detail_start = min(16, expected - 1)
    detail_end = max(detail_start + 1, expected - 8)
    dark_contact = qa / "contact-dark-every4f.jpg"
    light_contact = qa / "contact-light-every4f.jpg"
    detail_contact = qa / f"contact-dark-source{detail_start:03d}-{detail_end:03d}-every2f.jpg"
    base.contact_sheet(frames, indexes, (26, 29, 35)).save(dark_contact, quality=94)
    base.contact_sheet(frames, indexes, (245, 245, 245)).save(light_contact, quality=94)
    base.contact_sheet(frames, list(range(detail_start, detail_end + 1, 2)), (26, 29, 35)).save(
        detail_contact, quality=95
    )

    consecutive = [base.difference(frames[index], frames[index + 1]) for index in range(expected - 1)]
    margins = {
        side: min(int(item["margins"][side]) for item in frame_metrics)
        for side in ("left", "right", "top", "bottom")
    }
    outer_alpha_by_side = {
        side: max(int(item["outerEightPixelAlphaMaxBySide"][side]) for item in frame_metrics)
        for side in ("left", "right", "top", "bottom")
    }
    outer_alpha = max(outer_alpha_by_side.values())
    visible_areas = np.asarray([int(item["visibleArea"]) for item in frame_metrics])
    median_visible_area = float(np.median(visible_areas))
    minimum_visible_area = int(visible_areas.min())
    minimum_visible_area_frame = int(visible_areas.argmin())
    minimum_visible_area_ratio = minimum_visible_area / max(1.0, median_visible_area)
    minimum_margin = int(config.get("minimumMarginPx", 8))
    allowed_boundary_sides = set(config.get("allowedForegroundBoundarySides", []))
    known_sides = {"left", "right", "top", "bottom"}
    if not allowed_boundary_sides <= known_sides:
        raise RuntimeError("allowedForegroundBoundarySides contains an unknown side")
    disallowed_boundary_sides = known_sides - allowed_boundary_sides
    disallowed_boundary_contact = any(
        outer_alpha_by_side[side] > 0 or margins[side] < minimum_margin
        for side in disallowed_boundary_sides
    )
    declared_boundary_contact = any(
        outer_alpha_by_side[side] > 0 or margins[side] < minimum_margin
        for side in allowed_boundary_sides
    )
    source_endpoint_difference = base.difference(frames[0], source_endpoint)
    penultimate_target_difference = base.difference(frames[-2], target_endpoint)
    last_target_difference = base.difference(frames[-1], target_endpoint)
    maximum_source_endpoint_difference = float(
        config.get("maximumSourceEndpointDifference", 0.015)
    )
    maximum_target_endpoint_difference = float(
        config.get("maximumTargetEndpointDifference", 0.015)
    )
    if minimum_visible_area_ratio < float(config.get("minimumVisibleAreaRatio", 0.35)):
        status = "mechanical-fail-subject-disappearance"
    elif disallowed_boundary_contact:
        status = "mechanical-fail-fixed-crop-clipping"
    elif source_endpoint_difference > maximum_source_endpoint_difference or min(
        penultimate_target_difference,
        last_target_difference,
    ) > maximum_target_endpoint_difference:
        status = "mechanical-fail-endpoint-seam"
    elif declared_boundary_contact:
        status = "mechanical-pass-declared-scene-boundary-pending-internal-visual-review"
    else:
        status = "mechanical-pass-pending-internal-visual-review"
    preview_stem = config.get("previewStem", f"{config['edgeId']}-{job.name}-chain")
    report = {
        "schema": 1,
        "edgeId": config["edgeId"],
        "variant": job.name,
        "status": status,
        "humanApproved": False,
        "source": {
            "path": f"../artifacts/{source.name}",
            "sha256": sha256(source),
            "frames": len(frames),
            "fps": fps,
            "canvas": list(Image.open(raw_paths[0]).size),
        },
        "processing": {
            "sourceFramesModified": False,
            "compiledCopy": f"fixed cyan key, then the same crop {list(crop)} for every frame",
            "compiledCanvas": list(frames[0].size),
            "perFrameRepositioning": False,
            "interpolation": False,
            "opticalFlow": False,
            "rife": False,
            "bones": False,
            "crossfade": False,
            "reversePlayback": False,
            "mirroring": False,
            "sharedRuntimeTranslationAfterCrop": config.get("runtimeTranslationAfterCrop", [0, 0]),
            "endpointEmbedOffsetForComparison": list(endpoint_offset),
            "endpointCropForComparison": list(endpoint_crop) if endpoint_crop else None,
            "targetLoopEmbedOffset": list(target_loop_offset),
            "targetLoopCrop": list(target_loop_crop) if target_loop_crop else None,
        },
        "runtimeContract": {
            "from": config["from"],
            "to": config["to"],
            "ordinaryAutonomousInterruptible": False,
            "directControlInterruptible": False,
            "rootMotion": {"dxPerFrame": 0, "dyPerFrame": 0},
            "preloadTargetBeforePlayback": config["preloadTargetBeforePlayback"],
            "targetRuntimeFrame": int(config.get("targetRuntimeFrame", 0)),
            "canvasAnchorPx": config.get("canvasAnchorPx"),
        },
        "compiledClip": {
            "minimumMargins": margins,
            "outerEightPixelAlphaMax": outer_alpha,
            "outerEightPixelAlphaMaxBySide": outer_alpha_by_side,
            "allowedForegroundBoundarySides": sorted(allowed_boundary_sides),
            "subjectVisibility": {
                "minimumVisibleArea": minimum_visible_area,
                "medianVisibleArea": round(median_visible_area, 3),
                "minimumToMedianRatio": round(minimum_visible_area_ratio, 6),
                "minimumAtSourceFrame": minimum_visible_area_frame,
            },
            "consecutivePremultipliedDifference": {
                "mean": round(float(np.mean(consecutive)), 6),
                "p95": round(float(np.percentile(consecutive, 95)), 6),
                "max": round(float(np.max(consecutive)), 6),
                "maxAtTransition": int(np.argmax(consecutive)),
            },
        },
        "endpointEvidence": {
            "compiledFrame0VsSourceInput": round(source_endpoint_difference, 6),
            "compiledPenultimateVsTargetInput": round(penultimate_target_difference, 6),
            "compiledLastVsTargetInput": round(last_target_difference, 6),
            "targetRuntime0VsTargetInput": round(base.difference(target_loop[0], target_endpoint), 6),
            "maximumSourceEndpointDifference": maximum_source_endpoint_difference,
            "maximumTargetEndpointDifference": maximum_target_endpoint_difference,
        },
        "reviewArtifacts": {
            "contactDark": {"path": dark_contact.name, "sha256": sha256(dark_contact)},
            "contactLight": {"path": light_contact.name, "sha256": sha256(light_contact)},
            "contactDetail": {"path": detail_contact.name, "sha256": sha256(detail_contact)},
            "normal": base.encode(chain, preview_stem, fps),
            "twoTimesSlow": base.encode(chain, f"{preview_stem}-2x-slow", fps // 2),
        },
        "frames": frame_metrics,
        "mechanicalLimit": "fixed-crop bounds and endpoint similarity cannot prove anatomy, identity, tail continuity, weight transfer or natural motion",
    }
    base.write_json(qa / "candidate-report.json", report)
    print(json.dumps({key: value for key, value in report.items() if key != "frames"}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
