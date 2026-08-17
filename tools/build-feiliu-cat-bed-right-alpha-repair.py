#!/usr/bin/env python3
"""Repair only over-matted mint pixels on Feiliu's cat-bed right side.

The accepted pet pixels, source timing, frame order, fixed transforms and
presentation geometry remain unchanged.  The repair can only increase alpha
for large mint-colored components proven by the approved rough alpha and the
authoritative unmatted source frame.
"""

from __future__ import annotations

import argparse
from datetime import datetime
from fractions import Fraction
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
from typing import Any
from zoneinfo import ZoneInfo

import numpy as np
from PIL import Image
from scipy import ndimage


ROOT = Path(__file__).resolve().parents[1]
GOAL = ROOT / "workspaces/feiliu-private/goal-2026-08-16"
FINAL_MANIFEST = GOAL / "feiliu-selective-fine-matte-graph-tour-v2/manifest.json"
LOCK_MANIFEST = GOAL / "feiliu-fine-matte-input-lock-v1/manifest.json"
SOURCE_BUILDER = ROOT / "tools/build-feiliu-source-package.py"
FFMPEG = "/opt/homebrew/bin/ffmpeg"
SCHEMA_VERSION = "0.4.0"

MIN_SOURCE_X = 480
MIN_SOURCE_Y = 480
MIN_RED = 35
MIN_CYAN_EXCESS = 30
MIN_COMPONENT_PIXELS = 80
MIN_BED_CORE_PIXELS = 1000
BED_SUPPORT_DILATION_PX = 48


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-package", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    return parser.parse_args()


def within_repo(path: Path, *, strict: bool) -> Path:
    result = path if path.is_absolute() else ROOT / path
    result = result.resolve(strict=strict)
    result.relative_to(ROOT)
    return result


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sequence_digest(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in paths:
        digest.update(path.name.encode("utf-8"))
        digest.update(b"\0")
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        digest.update(b"\n")
    return digest.hexdigest()


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


source_builder = load_module("feiliu_source_builder_for_cat_bed_repair", SOURCE_BUILDER)


def validate_regular_file(path: Path) -> None:
    hidden_mask = getattr(stat, "UF_HIDDEN", 0)
    if (
        path.name.startswith(".")
        or bool(path.lstat().st_flags & hidden_mask)
        or not path.is_file()
        or path.is_symlink()
    ):
        raise ValueError(f"hidden, symlinked or non-regular package file: {path}")


def verify_integrity(package: Path) -> None:
    integrity = read_json(package / "integrity.json")
    if str(integrity.get("algorithm", "")).lower() != "sha256":
        raise ValueError("source package does not use SHA-256 integrity")
    for entry in integrity.get("files", []):
        relative = Path(str(entry["path"]))
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"unsafe integrity path: {relative}")
        path = package / relative
        validate_regular_file(path)
        if path.stat().st_size != int(entry["bytes"]):
            raise ValueError(f"source byte count mismatch: {relative}")
        if sha256(path) != str(entry["sha256"]).lower():
            raise ValueError(f"source SHA-256 mismatch: {relative}")


def integrity_manifest(root: Path) -> dict[str, Any]:
    entries = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.name == "integrity.json":
            continue
        validate_regular_file(path)
        entries.append(
            {
                "path": path.relative_to(root).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
        )
    return {"schemaVersion": SCHEMA_VERSION, "algorithm": "sha256", "files": entries}


def copy_with_links(source: Path, destination: Path) -> None:
    def copy_file(src: str, dst: str) -> str:
        source_path = Path(src)
        destination_path = Path(dst)
        if source_path.suffix.lower() == ".png":
            os.link(source_path, destination_path)
            return str(destination_path)
        return shutil.copy2(source_path, destination_path)

    shutil.copytree(source, destination, copy_function=copy_file)


def decode_source(record: dict[str, Any], output: Path) -> list[Path]:
    source = ROOT / str(record["source"])
    if sha256(source) != str(record["sourceSha256"]):
        raise ValueError(f"source hash drift: {record['clipId']}")
    output.mkdir()
    if source.suffix.lower() == ".png":
        Image.open(source).convert("RGB").save(output / "000001.png", compress_level=4)
        paths = [output / "000001.png"]
    else:
        subprocess.run(
            [
                FFMPEG,
                "-hide_banner",
                "-loglevel",
                "error",
                "-i",
                str(source),
                "-vsync",
                "0",
                str(output / "%06d.png"),
            ],
            check=True,
        )
        paths = sorted(output.glob("*.png"))
        selected = record.get("selectedSourceFrameRangeInclusive")
        if selected:
            paths = paths[int(selected[0]) : int(selected[1]) + 1]
    if len(paths) != int(record["selectedFrameCount"]):
        raise ValueError(f"selected source frame mismatch: {record['clipId']}")
    return paths


def repair_mint_bed_right(
    source_rgb: np.ndarray,
    accepted_rgba: np.ndarray,
    rough_alpha: np.ndarray,
    *,
    temporal_bed_presence_selected: bool,
) -> tuple[np.ndarray, dict[str, Any]]:
    if source_rgb.shape[:2] != rough_alpha.shape or accepted_rgba.shape[:2] != rough_alpha.shape:
        raise ValueError("repair input dimensions do not match")
    y, x = np.indices(rough_alpha.shape)
    red, green, blue = np.moveaxis(source_rgb.astype(np.int16), 2, 0)
    alpha = accepted_rgba[..., 3]
    current_mint_core = (
        (alpha >= 128)
        & (x >= MIN_SOURCE_X)
        & (y >= MIN_SOURCE_Y)
        & (red >= MIN_RED)
        & ((green - red) >= MIN_CYAN_EXCESS)
        & ((blue - red) >= MIN_CYAN_EXCESS)
    )
    core_labels, core_count = ndimage.label(current_mint_core)
    core_sizes = np.bincount(core_labels.ravel())
    if core_count:
        largest_core_label = int(np.argmax(core_sizes[1:]) + 1)
        largest_core_pixels = int(core_sizes[largest_core_label])
    else:
        largest_core_label = 0
        largest_core_pixels = 0
    if temporal_bed_presence_selected and largest_core_pixels >= MIN_BED_CORE_PIXELS:
        bed_support = ndimage.binary_dilation(
            core_labels == largest_core_label,
            iterations=BED_SUPPORT_DILATION_PX,
        )
    else:
        bed_support = np.zeros(rough_alpha.shape, dtype=bool)

    candidate = (
        (rough_alpha > alpha)
        & bed_support
        & (x >= MIN_SOURCE_X)
        & (y >= MIN_SOURCE_Y)
        & (red >= MIN_RED)
        & ((green - red) >= MIN_CYAN_EXCESS)
        & ((blue - red) >= MIN_CYAN_EXCESS)
    )
    labels, count = ndimage.label(candidate)
    sizes = np.bincount(labels.ravel())
    accepted_labels = np.where(sizes >= MIN_COMPONENT_PIXELS)[0]
    accepted_labels = accepted_labels[accepted_labels != 0]
    recovery = np.isin(labels, accepted_labels)

    repaired = accepted_rgba.copy()
    repaired[recovery, :3] = source_rgb[recovery]
    recovered_alpha = np.where(recovery, rough_alpha, 0).astype(np.uint8)
    repaired[..., 3] = np.maximum(repaired[..., 3], recovered_alpha)

    changed = np.any(repaired != accepted_rgba, axis=2)
    if np.any(changed & ~recovery):
        raise RuntimeError("repair changed pixels outside the mint bed mask")
    if np.any(repaired[..., 3] < accepted_rgba[..., 3]):
        raise RuntimeError("repair decreased accepted alpha")
    if np.any(repaired[~recovery] != accepted_rgba[~recovery]):
        raise RuntimeError("accepted pet and non-repair pixels changed")

    changed_y, changed_x = np.where(changed)
    return repaired, {
        "candidateComponents": int(count),
        "acceptedComponents": int(len(accepted_labels)),
        "largestAcceptedMintBedCorePixels": largest_core_pixels,
        "bedPresenceGatePassed": (
            temporal_bed_presence_selected
            and largest_core_pixels >= MIN_BED_CORE_PIXELS
        ),
        "temporalBedPresenceSelected": temporal_bed_presence_selected,
        "recoveredPixels": int(recovery.sum()),
        "changedPixels": int(changed.sum()),
        "changedBoundsSourcePx": (
            [
                int(changed_x.min()),
                int(changed_y.min()),
                int(changed_x.max()) + 1,
                int(changed_y.max()) + 1,
            ]
            if len(changed_x)
            else None
        ),
    }


def largest_mint_core_pixels(source_rgb: np.ndarray, accepted_rgba: np.ndarray) -> int:
    y, x = np.indices(accepted_rgba.shape[:2])
    red, green, blue = np.moveaxis(source_rgb.astype(np.int16), 2, 0)
    core = (
        (accepted_rgba[..., 3] >= 128)
        & (x >= MIN_SOURCE_X)
        & (y >= MIN_SOURCE_Y)
        & (red >= MIN_RED)
        & ((green - red) >= MIN_CYAN_EXCESS)
        & ((blue - red) >= MIN_CYAN_EXCESS)
    )
    labels, count = ndimage.label(core)
    if not count:
        return 0
    sizes = np.bincount(labels.ravel())
    return int(sizes[1:].max())


def longest_bed_presence_run(core_pixels: list[int]) -> tuple[int, int] | None:
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for index, pixels in enumerate(core_pixels + [0]):
        if pixels >= MIN_BED_CORE_PIXELS and start is None:
            start = index
        if pixels < MIN_BED_CORE_PIXELS and start is not None:
            runs.append((start, index - 1))
            start = None
    if not runs:
        return None
    return max(runs, key=lambda run: (run[1] - run[0] + 1, -run[0]))


def compile_image(image: Image.Image, transform: dict[str, Any]) -> Image.Image:
    scale = float(transform["uniformScale"])
    scaled = source_builder.premultiplied_resize(
        image,
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
    )
    tx, ty = [round(float(value)) for value in transform["translatePx"]]
    master = Image.new("RGBA", source_builder.MASTER_CANVAS, (0, 0, 0, 0))
    master.alpha_composite(scaled, (tx, ty))
    cropped = master.crop(source_builder.MASTER_CROP)
    return source_builder.premultiplied_resize(cropped, source_builder.OUTPUT_CANVAS)


def cat_bed_clip_ids(graph: dict[str, Any]) -> set[str]:
    node_scene = {str(node["id"]): str(node.get("scene", "")) for node in graph.get("nodes", [])}
    result = {
        str(node["loopClip"])
        for node in graph.get("nodes", [])
        if node_scene.get(str(node["id"])) == "cat-bed"
    }
    result.update(
        str(edge["clip"])
        for edge in graph.get("edges", [])
        if node_scene.get(str(edge["from"])) == "cat-bed"
        or node_scene.get(str(edge["to"])) == "cat-bed"
    )
    return result


def main() -> None:
    args = parse_args()
    source_package = within_repo(args.source_package, strict=True)
    output = within_repo(args.output, strict=False)
    if source_package.suffix != ".petsgraph-pet" or not source_package.is_dir():
        raise ValueError("--source-package must be a package directory")
    if output.suffix != ".petsgraph-pet":
        raise ValueError("--output must end in .petsgraph-pet")
    if output.exists():
        raise FileExistsError(f"refusing to overwrite {output}")
    verify_integrity(source_package)

    final = read_json(FINAL_MANIFEST)
    if final.get("status") != "human-approved-selective-fine-matte-graph-tour":
        raise ValueError("accepted fine-matte graph status drift")
    approved_records = {str(item["clipId"]): item for item in final["uniqueRecords"]}
    lock = read_json(LOCK_MANIFEST)
    locked_records = {str(item["clipId"]): item for item in lock["records"]}
    graph = read_json(source_package / "graph.json")
    affected_ids = cat_bed_clip_ids(graph)
    if len(affected_ids) != 15:
        raise ValueError(f"expected 15 cat-bed clips, found {len(affected_ids)}")
    if not affected_ids <= approved_records.keys() or not affected_ids <= locked_records.keys():
        raise ValueError("cat-bed graph clips are missing accepted source records")

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f"{output.name}.build-", dir=output.parent))
    summaries = []
    try:
        shutil.rmtree(temporary)
        copy_with_links(source_package, temporary)
        for clip_id in sorted(affected_ids):
            accepted_record = approved_records[clip_id]
            accepted_manifest_path = ROOT / str(accepted_record["manifest"])
            if sha256(accepted_manifest_path) != str(accepted_record["manifestSha256"]):
                raise ValueError(f"accepted recipe hash drift: {clip_id}")
            accepted_manifest = read_json(accepted_manifest_path)
            if accepted_manifest.get("fixedTransform") != accepted_record.get("fixedTransform"):
                raise ValueError(f"fixed transform drift: {clip_id}")
            accepted_rgba_paths = sorted(
                (accepted_manifest_path.parent / "clips" / clip_id / "rgba").glob("*.png")
            )
            lock_record = locked_records[clip_id]
            rough_paths = sorted((ROOT / str(lock_record["roughAlphaFrames"])).glob("*.png"))
            if len(accepted_rgba_paths) != len(rough_paths):
                raise ValueError(f"accepted RGBA/rough alpha mismatch: {clip_id}")
            source_frame_dir = temporary / "frames" / clip_id
            previous_package_paths = sorted((source_package / "frames" / clip_id).glob("*.png"))
            if len(previous_package_paths) != len(accepted_rgba_paths):
                raise ValueError(f"source package frame mismatch: {clip_id}")
            previous_package_hashes = [sha256(path) for path in previous_package_paths]
            shutil.rmtree(source_frame_dir)
            source_frame_dir.mkdir()

            frame_stats = []
            with tempfile.TemporaryDirectory(prefix=f"petsgraph-cat-bed-repair-{clip_id}-") as scratch_text:
                source_paths = decode_source(lock_record, Path(scratch_text) / "source")
                if len(source_paths) != len(accepted_rgba_paths):
                    raise ValueError(f"unmatted source/accepted RGBA mismatch: {clip_id}")
                core_pixels = [
                    largest_mint_core_pixels(
                        np.asarray(Image.open(source_path).convert("RGB"), dtype=np.uint8),
                        np.asarray(Image.open(accepted_path).convert("RGBA"), dtype=np.uint8),
                    )
                    for source_path, accepted_path in zip(
                        source_paths,
                        accepted_rgba_paths,
                        strict=True,
                    )
                ]
                bed_presence_run = longest_bed_presence_run(core_pixels)
                for index, (source_path, accepted_path, rough_path) in enumerate(
                    zip(source_paths, accepted_rgba_paths, rough_paths, strict=True)
                ):
                    source_rgb = np.asarray(Image.open(source_path).convert("RGB"), dtype=np.uint8)
                    accepted_rgba = np.asarray(Image.open(accepted_path).convert("RGBA"), dtype=np.uint8)
                    rough_alpha = np.asarray(Image.open(rough_path).convert("L"), dtype=np.uint8)
                    with Image.open(previous_package_paths[index]) as previous:
                        baseline_compiled = np.asarray(previous.convert("RGBA"), dtype=np.uint8)
                    temporal_bed_presence_selected = bool(
                        bed_presence_run
                        and bed_presence_run[0] <= index <= bed_presence_run[1]
                    )
                    repaired_rgba, stats = repair_mint_bed_right(
                        source_rgb,
                        accepted_rgba,
                        rough_alpha,
                        temporal_bed_presence_selected=temporal_bed_presence_selected,
                    )
                    compiled_candidate = np.asarray(
                        compile_image(
                            Image.fromarray(repaired_rgba, "RGBA"),
                            accepted_record["fixedTransform"],
                        ),
                        dtype=np.uint8,
                    )
                    alpha_increase = compiled_candidate[..., 3] > baseline_compiled[..., 3]
                    compiled_locked = baseline_compiled.copy()
                    compiled_locked[alpha_increase] = compiled_candidate[alpha_increase]
                    if np.any(compiled_locked[..., 3] < baseline_compiled[..., 3]):
                        raise RuntimeError(f"compiled alpha decreased: {clip_id} frame {index + 1}")
                    if np.any(compiled_locked[~alpha_increase] != baseline_compiled[~alpha_increase]):
                        raise RuntimeError(f"compiled accepted pixels changed: {clip_id} frame {index + 1}")
                    destination = source_frame_dir / f"{index:04d}.png"
                    Image.fromarray(compiled_locked, "RGBA").save(
                        destination,
                        format="PNG",
                        optimize=True,
                    )
                    stats["frame"] = index + 1
                    stats["compiledAlphaIncreasePixels"] = int(alpha_increase.sum())
                    frame_stats.append(stats)

            repaired_paths = sorted(source_frame_dir.glob("*.png"))
            changed_frames = [
                index + 1
                for index, (before_hash, after_path) in enumerate(zip(previous_package_hashes, repaired_paths, strict=True))
                if before_hash != sha256(after_path)
            ]
            clip_path = temporary / "clips" / f"{clip_id}.json"
            clip = read_json(clip_path)
            if len(clip.get("frames", [])) != len(repaired_paths):
                raise ValueError(f"clip contract frame mismatch: {clip_id}")
            for frame, frame_path in zip(clip["frames"], repaired_paths, strict=True):
                if frame.get("src") != frame_path.relative_to(temporary).as_posix():
                    raise ValueError(f"clip source path drift: {clip_id}")
            provenance = clip.setdefault("provenance", {})
            provenance["approvalStatus"] = "cat-bed-right-alpha-repair-awaiting-Maxwell-visual-review"
            provenance["sourceSequenceDigest"] = sequence_digest(repaired_paths)
            provenance["catBedRightAlphaRepair"] = {
                "scope": "mint cat-bed right-side pixels only",
                "operation": "alpha increase plus authoritative source RGB recovery",
                "sourceSpaceLimitsPx": {"minimumX": MIN_SOURCE_X, "minimumY": MIN_SOURCE_Y},
                "colorGate": {
                    "minimumRed": MIN_RED,
                    "minimumGreenMinusRed": MIN_CYAN_EXCESS,
                    "minimumBlueMinusRed": MIN_CYAN_EXCESS,
                },
                "minimumConnectedComponentPixels": MIN_COMPONENT_PIXELS,
                "minimumAcceptedMintBedCorePixels": MIN_BED_CORE_PIXELS,
                "bedSupportDilationPx": BED_SUPPORT_DILATION_PX,
                "temporalBedPresenceGate": "longest-contiguous-core-run",
                "petPixelsRecomputed": False,
                "acceptedPixelsOutsideRecoveryMaskChanged": False,
                "alphaDecreased": False,
                "compiledExistingPixelsChangedWithoutAlphaIncrease": False,
                "fixedTransformChanged": False,
                "frameOrderChanged": False,
                "frameTimingChanged": False,
            }
            write_json(clip_path, clip)
            summaries.append(
                {
                    "clipId": clip_id,
                    "frameCount": len(repaired_paths),
                    "changedFrameCount": len(changed_frames),
                    "changedFrames": changed_frames,
                    "totalRecoveredPixelsSourceSpace": sum(item["recoveredPixels"] for item in frame_stats),
                    "maximumRecoveredPixelsInFrame": max(item["recoveredPixels"] for item in frame_stats),
                    "selectedBedPresenceFrameRangeInclusive": (
                        [bed_presence_run[0] + 1, bed_presence_run[1] + 1]
                        if bed_presence_run
                        else None
                    ),
                    "frames": frame_stats,
                    "repairedPackageSequenceDigest": sequence_digest(repaired_paths),
                }
            )

        package_manifest = read_json(temporary / "package.json")
        package_manifest["package"]["version"] = args.version
        package_manifest["package"]["createdAt"] = datetime.now(
            ZoneInfo("Asia/Shanghai")
        ).strftime("%Y-%m-%dT%H:%M:%S%z")
        write_json(temporary / "package.json", package_manifest)

        review_path = temporary / "reviews" / "index.json"
        review = read_json(review_path)
        review["runtimeChainStatus"] = "cat-bed-right-alpha-repair-awaiting-human-review"
        review["installable"] = False
        remaining = list(review.get("remainingRuntimeGates", []))
        gate = "Feiliu cat-bed right-side alpha repair full-clip visual review"
        if gate not in remaining:
            remaining.append(gate)
        review["remainingRuntimeGates"] = remaining
        write_json(review_path, review)

        source_assets_path = temporary / "source-assets.json"
        source_assets = read_json(source_assets_path)
        source_assets.setdefault("derivation", {})["catBedRightAlphaRepair"] = {
            "status": "assistant-qa-pending-Maxwell-visual-review",
            "affectedClipCount": len(summaries),
            "sourcePixelsRegenerated": False,
            "seedanceCalled": False,
            "petPixelsRecomputed": False,
            "scaleOrTranslationChanged": False,
            "frameOrderOrTimingChanged": False,
            "recipe": {
                "minimumSourceX": MIN_SOURCE_X,
                "minimumSourceY": MIN_SOURCE_Y,
                "minimumRed": MIN_RED,
                "minimumCyanExcess": MIN_CYAN_EXCESS,
                "minimumConnectedComponentPixels": MIN_COMPONENT_PIXELS,
                "minimumAcceptedMintBedCorePixels": MIN_BED_CORE_PIXELS,
                "bedSupportDilationPx": BED_SUPPORT_DILATION_PX,
                "temporalBedPresenceGate": "longest-contiguous-core-run",
            },
            "clips": summaries,
        }
        write_json(source_assets_path, source_assets)
        write_json(temporary / "cat-bed-right-alpha-repair.json", {
            "schemaVersion": SCHEMA_VERSION,
            "status": "built-awaiting-Maxwell-visual-review",
            "affectedClipCount": len(summaries),
            "clips": summaries,
        })
        (temporary / "integrity.json").unlink()
        write_json(temporary / "integrity.json", integrity_manifest(temporary))
        temporary.rename(output)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise

    print(
        json.dumps(
            {
                "output": output.as_posix(),
                "version": args.version,
                "affectedClipCount": len(summaries),
                "changedClipCount": sum(bool(item["changedFrameCount"]) for item in summaries),
                "totalRecoveredPixelsSourceSpace": sum(item["totalRecoveredPixelsSourceSpace"] for item in summaries),
                "status": "built-awaiting-Maxwell-visual-review",
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
