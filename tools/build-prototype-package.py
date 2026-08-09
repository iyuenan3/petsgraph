#!/usr/bin/env python3

"""Compile approved RGBA frame sequences into a local petsgraph prototype package."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import stat
import tempfile
from typing import Any

from PIL import Image


SCHEMA_VERSION = "0.1.0"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--walk-speed-override", type=float)
    parser.add_argument("--package-version-override")
    parser.add_argument("--created-at-override")
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_repo_path(repo_root: Path, relative: str) -> Path:
    if not relative or Path(relative).is_absolute() or ".." in Path(relative).parts:
        raise ValueError(f"unsafe source path: {relative}")
    resolved = (repo_root / relative).resolve(strict=True)
    resolved.relative_to(repo_root)
    return resolved


def ordered_sequence_digest(frames: list[Path]) -> str:
    digest = hashlib.sha256()
    for frame in frames:
        digest.update(frame.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(sha256(frame).encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def validate_approved_recipe(
    repo_root: Path,
    clip_config: dict[str, Any],
    source: Path,
) -> None:
    expected_recipe_digest = clip_config.get("approvedRecipeSha256")
    if expected_recipe_digest is None:
        return

    recipe_path = safe_repo_path(repo_root, clip_config["approvedRecipe"])
    actual_recipe_digest = sha256(recipe_path)
    if actual_recipe_digest != expected_recipe_digest.lower():
        raise ValueError(
            f"{recipe_path} approved recipe digest mismatch: {actual_recipe_digest}"
        )

    recipe = read_json(recipe_path)
    expected_subject = clip_config.get("approvalSubjectId")
    actual_subject = recipe.get("subjectId") or recipe.get("edgeId")
    if expected_subject is not None and actual_subject != expected_subject:
        raise ValueError(
            f"{recipe_path} declares subject {actual_subject}, "
            f"expected {expected_subject}"
        )
    approval_status = recipe.get("approval", {}).get("status") or recipe.get("status")
    if approval_status != clip_config["approvalStatus"]:
        raise ValueError(
            f"{recipe_path} approval status {approval_status}, "
            f"expected {clip_config['approvalStatus']}"
        )

    selection = recipe.get("selection", {})
    selected_frames = selection.get("selectedFrames")
    if selected_frames is None:
        selected_frames = selection.get("runtimeFrames")
    if selected_frames is None:
        selected_frames = recipe.get("factSource", {}).get("frames")
    if int(selected_frames if selected_frames is not None else -1) != int(clip_config["frameCount"]):
        raise ValueError(f"{recipe_path} approved frame count does not match clip config")
    approved_fps = selection.get("fps")
    if approved_fps is None:
        approved_fps = recipe.get("source", {}).get("fps")
    if approved_fps is None:
        approved_fps = recipe.get("generation", {}).get("sourceVideo", {}).get("fps")
    if not math.isclose(
        float(approved_fps if approved_fps is not None else -1),
        float(clip_config.get("fps", 24)),
    ):
        raise ValueError(f"{recipe_path} approved FPS does not match clip config")

    fact_source = recipe.get("factSource") or selection.get("factSource")
    if not isinstance(fact_source, dict):
        raise ValueError(f"{recipe_path} does not declare an approved fact source")
    approved_source = (recipe_path.parent / fact_source["path"]).resolve(strict=True)
    if approved_source != source:
        raise ValueError(
            f"{recipe_path} fact source {approved_source} does not match {source}"
        )
    expected_sequence_digest = clip_config.get("sourceSequenceDigest")
    if fact_source.get("orderedSequenceDigest") != expected_sequence_digest:
        raise ValueError(
            f"{recipe_path} approved sequence digest does not match clip config"
        )


def frame_paths(
    source: Path,
    expected: int,
    expected_digest: str | None = None,
) -> list[Path]:
    frames = sorted(source.glob("frame-*.png"))
    if len(frames) != expected:
        raise ValueError(
            f"{source} expected {expected} PNG frames but found {len(frames)}"
        )
    expected_names = [f"frame-{index:03d}.png" for index in range(expected)]
    if [frame.name for frame in frames] != expected_names:
        raise ValueError(f"{source} frame names are not a contiguous zero-based sequence")
    if expected_digest is not None:
        actual_digest = ordered_sequence_digest(frames)
        if actual_digest != expected_digest.lower():
            raise ValueError(
                f"{source} approved sequence digest mismatch: {actual_digest}"
            )
    return frames


def transform_about_anchor(
    image: Image.Image,
    scale: float,
    anchor: tuple[float, float],
) -> Image.Image:
    if abs(scale - 1.0) < 1e-9:
        return image
    canvas_width, canvas_height = image.size
    resized = image.resize(
        (
            max(1, round(canvas_width * scale)),
            max(1, round(canvas_height * scale)),
        ),
        Image.Resampling.LANCZOS,
    )
    offset = (
        round(anchor[0] - anchor[0] * scale),
        round(anchor[1] - anchor[1] * scale),
    )
    canvas = Image.new("RGBA", image.size, (0, 0, 0, 0))
    canvas.alpha_composite(resized, dest=offset)
    return canvas


def runtime_frame(
    source: Path,
    source_canvas: tuple[int, int],
    runtime_canvas: tuple[int, int],
    transform: dict[str, Any],
    compilation_canvas: tuple[int, int] | None = None,
    source_placement: tuple[int, int] = (0, 0),
) -> Image.Image:
    image = Image.open(source).convert("RGBA")
    if image.size != source_canvas:
        raise ValueError(f"{source} is {image.size}, expected {source_canvas}")
    image = transform_about_anchor(
        image,
        float(transform.get("scale", 1.0)),
        tuple(float(value) for value in transform.get("anchorPx", [320, 532])),
    )
    translation = tuple(float(value) for value in transform.get("translatePx", [0, 0]))
    if len(translation) != 2 or any(not value.is_integer() for value in translation):
        raise ValueError("translatePx must contain two integer source-pixel offsets")
    if translation != (0.0, 0.0):
        translated = Image.new("RGBA", image.size, (0, 0, 0, 0))
        translated.alpha_composite(
            image,
            dest=(int(translation[0]), int(translation[1])),
        )
        image = translated
    crop = transform.get("cropPx")
    if crop is not None:
        if len(crop) != 4 or any(not float(value).is_integer() for value in crop):
            raise ValueError("cropPx must contain four integer source-pixel values")
        left, top, width, height = (int(value) for value in crop)
        if left < 0 or top < 0 or width <= 0 or height <= 0:
            raise ValueError("cropPx must describe a positive in-bounds rectangle")
        if left + width > image.width or top + height > image.height:
            raise ValueError("cropPx escapes the transformed source canvas")
        image = image.crop((left, top, left + width, top + height))
    if compilation_canvas is not None and image.size != compilation_canvas:
        placement = transform.get("compilePlacementPx", source_placement)
        if len(placement) != 2 or any(not float(value).is_integer() for value in placement):
            raise ValueError("compilePlacementPx must contain two integer values")
        offset = tuple(int(value) for value in placement)
        if (
            offset[0] < 0
            or offset[1] < 0
            or offset[0] + image.width > compilation_canvas[0]
            or offset[1] + image.height > compilation_canvas[1]
        ):
            raise ValueError("compiled source placement escapes compilationCanvasPx")
        compiled = Image.new("RGBA", compilation_canvas, (0, 0, 0, 0))
        compiled.alpha_composite(image, dest=offset)
        image = compiled
    if image.size != runtime_canvas:
        image = image.resize(runtime_canvas, Image.Resampling.LANCZOS)
    return image


def motion_at(profile: dict[str, Any], time_seconds: float, duration: float) -> float:
    kind = profile["kind"]
    if kind == "stationary":
        return 0.0
    if kind == "constant":
        return float(profile["speedPtPerSecond"]) * time_seconds
    if kind == "smooth-speed":
        start = float(profile["startSpeedPtPerSecond"])
        end = float(profile["endSpeedPtPerSecond"])
        u = min(1.0, max(0.0, time_seconds / duration))
        integrated_smoothstep = u**3 - 0.5 * u**4
        return start * duration * u + (end - start) * duration * integrated_smoothstep
    if kind == "delayed-smooth-speed":
        delay = float(profile["delaySeconds"])
        if delay < 0 or delay >= duration:
            raise ValueError("delayed smooth speed requires 0 <= delay < duration")
        active_duration = duration - delay
        active_time = min(active_duration, max(0.0, time_seconds - delay))
        u = active_time / active_duration
        start = float(profile["startSpeedPtPerSecond"])
        end = float(profile["endSpeedPtPerSecond"])
        integrated_smoothstep = u**3 - 0.5 * u**4
        return (
            start * active_duration * u
            + (end - start) * active_duration * integrated_smoothstep
        )
    if kind == "piecewise-smooth-speed":
        delay = float(profile.get("delaySeconds", 0))
        ramp = float(profile["rampSeconds"])
        start = float(profile["startSpeedPtPerSecond"])
        end = float(profile["endSpeedPtPerSecond"])
        if delay < 0 or ramp <= 0 or delay + ramp > duration + 1e-9:
            raise ValueError(
                "piecewise smooth speed requires delay >= 0, ramp > 0 and delay + ramp <= duration"
            )
        clamped = min(duration, max(0.0, time_seconds))
        before_ramp = min(clamped, delay)
        ramp_time = min(ramp, max(0.0, clamped - delay))
        u = ramp_time / ramp
        integrated_smoothstep = u**3 - 0.5 * u**4
        ramp_motion = start * ramp * u + (end - start) * ramp * integrated_smoothstep
        after_ramp = max(0.0, clamped - delay - ramp)
        return start * before_ramp + ramp_motion + end * after_ramp
    raise ValueError(f"unsupported motion profile: {kind}")


def bounds_and_metadata(
    image: Image.Image,
    ground_y: float,
    facing: str,
) -> tuple[list[float], dict[str, list[float]], dict[str, list[float]]]:
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError("compiled frame has no visible alpha")
    left, top, right, bottom = bounds
    width = right - left
    height = bottom - top
    content = [float(left), float(top), float(width), float(height)]
    root_x = image.width / 2
    head_x = left + width * (0.80 if facing == "right" else 0.20)
    anchors = {
        "root": [round(root_x, 3), round(ground_y, 3)],
        "ground": [round(root_x, 3), round(ground_y, 3)],
        "head": [round(head_x, 3), round(top + height * 0.25, 3)],
    }
    collision = {
        "bodyCoreEllipsePx": [
            round(left + width * 0.16, 3),
            round(top + height * 0.27, 3),
            round(width * 0.68, 3),
            round(height * 0.50, 3),
        ],
        "screenBoundsPx": content,
    }
    return content, anchors, collision


def compile_clip(
    repo_root: Path,
    build_root: Path,
    config: dict[str, Any],
    source_canvas: tuple[int, int],
    runtime_canvas: tuple[int, int],
    ground_y: float,
    compilation_canvas: tuple[int, int] | None = None,
    source_placement: tuple[int, int] = (0, 0),
) -> dict[str, Any]:
    clip_id = config["id"]
    source = safe_repo_path(repo_root, config["source"])
    validate_approved_recipe(repo_root, config, source)
    sources = frame_paths(
        source,
        int(config["frameCount"]),
        config.get("sourceSequenceDigest"),
    )
    output_frames = build_root / "frames" / clip_id
    output_frames.mkdir(parents=True, exist_ok=True)

    fps = float(config.get("fps", 24))
    duration_ms = 1000.0 / fps
    total_duration = len(sources) / fps
    profile = config["motion"]
    clip_source_canvas = tuple(
        int(value) for value in config.get("sourceCanvasPx", source_canvas)
    )
    if len(clip_source_canvas) != 2:
        raise ValueError(f"{clip_id} sourceCanvasPx must contain two dimensions")
    frames: list[dict[str, Any]] = []
    for index, source_frame in enumerate(sources):
        image = runtime_frame(
            source_frame,
            clip_source_canvas,
            runtime_canvas,
            config.get("transform", {}),
            compilation_canvas,
            source_placement,
        )
        destination = output_frames / f"{index:04d}.png"
        image.save(destination, optimize=True)
        content, anchors, collision = bounds_and_metadata(
            image,
            ground_y,
            config["facing"],
        )
        motion_x = motion_at(profile, index / fps, total_duration)
        frames.append(
            {
                "src": destination.relative_to(build_root).as_posix(),
                "durationMs": round(duration_ms, 6),
                "contentBoundsPx": content,
                "anchorsPx": anchors,
                "collision": collision,
                "rootMotionPt": [round(motion_x, 6), 0.0],
            }
        )

    terminal_motion = motion_at(profile, total_duration, total_duration)
    clip = {
        "schemaVersion": SCHEMA_VERSION,
        "id": clip_id,
        "type": config["type"],
        "facing": config["facing"],
        "mirrorSafe": False,
        "entryPose": config["entryPose"],
        "exitPose": config["exitPose"],
        "safeExitFrames": config.get("safeExitFrames", []),
        "preloadHints": config.get("preloadHints", []),
        "rootMotionEndPt": [round(terminal_motion, 6), 0.0],
        "frames": frames,
        "provenance": {
            "approvalStatus": config["approvalStatus"],
            "approvedRecipe": config["approvedRecipe"],
            "approvedRecipeSha256": config.get("approvedRecipeSha256"),
            "rootMotionStatus": config.get(
                "rootMotionStatus",
                "provisional-calibrated-awaiting-runtime-review",
            ),
            "normalization": config.get("normalization", "approved-frame-canvas"),
        },
    }
    write_json(build_root / "clips" / f"{clip_id}.json", clip)
    return {
        "id": clip_id,
        "frames": len(frames),
        "durationSeconds": round(total_duration, 6),
        "rootMotionEndPt": round(terminal_motion, 6),
    }


def integrity_manifest(build_root: Path) -> dict[str, Any]:
    entries = []
    for path in sorted(build_root.rglob("*")):
        if not path.is_file() or path.name == "integrity.json":
            continue
        entries.append(
            {
                "path": path.relative_to(build_root).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
        )
    return {
        "schemaVersion": SCHEMA_VERSION,
        "algorithm": "sha256",
        "files": entries,
    }


def hidden_flagged_paths(root: Path) -> list[Path]:
    hidden_mask = getattr(stat, "UF_HIDDEN", 0)
    if hidden_mask == 0:
        return []
    candidates = [root, *sorted(root.rglob("*"))]
    return [path for path in candidates if path.lstat().st_flags & hidden_mask]


def assert_no_hidden_flags(root: Path) -> None:
    flagged = hidden_flagged_paths(root)
    if flagged:
        relative = [
            "." if path == root else path.relative_to(root).as_posix()
            for path in flagged
        ]
        raise ValueError(
            "compiled package contains hidden filesystem flags: "
            + ", ".join(relative)
        )


def install_build(build_root: Path, output: Path, created_at: str) -> Path | None:
    backup = None
    if output.exists():
        safe_stamp = created_at.replace(":", "").replace("+", "-")
        backup = output.with_name(f"{output.name}.previous-{safe_stamp}")
        if backup.exists():
            raise ValueError(f"backup already exists: {backup}")
        output.rename(backup)
    try:
        build_root.rename(output)
        assert_no_hidden_flags(output)
    except Exception:
        if output.exists() and not build_root.exists():
            output.rename(build_root)
        if backup is not None and not output.exists():
            backup.rename(output)
        raise
    return backup


def load_config(repo_root: Path, config_path: Path) -> dict[str, Any]:
    overlay = read_json(config_path)
    base_reference = overlay.get("extendsConfig")
    if base_reference is None:
        return overlay

    base_path = safe_repo_path(repo_root, base_reference)
    config = copy.deepcopy(load_config(repo_root, base_path))
    for key in (
        "schema",
        "package",
        "pet",
        "sourceCanvasPx",
        "compilationCanvasPx",
        "sourcePlacementPx",
        "runtimeCanvasPx",
        "sourceGroundYExclusivePx",
        "baseHeightPt",
        "defaultNode",
        "calibration",
        "demoSequence",
        "normalization",
        "graphConnectivity",
        "runtimeReview",
    ):
        if key in overlay:
            config[key] = copy.deepcopy(overlay[key])

    additions = overlay.get("graphAdditions", {})
    config["graph"]["nodes"].extend(copy.deepcopy(additions.get("nodes", [])))
    config["graph"]["edges"].extend(copy.deepcopy(additions.get("edges", [])))
    for update in overlay.get("graphEdgeUpdates", []):
        matches = [
            edge for edge in config["graph"]["edges"] if edge["id"] == update["id"]
        ]
        if len(matches) != 1:
            raise ValueError(f"graph edge update did not resolve exactly once: {update['id']}")
        matches[0].update(copy.deepcopy(update))
    for update in overlay.get("clipUpdates", []):
        matches = [clip for clip in config["clips"] if clip["id"] == update["id"]]
        if len(matches) != 1:
            raise ValueError(f"clip update did not resolve exactly once: {update['id']}")
        matches[0].update(copy.deepcopy(update))
    config["clips"].extend(copy.deepcopy(overlay.get("clips", [])))
    config["materialUnits"].extend(copy.deepcopy(overlay.get("materialUnits", [])))
    return config


def validate_config(config: dict[str, Any]) -> None:
    clip_ids = [clip["id"] for clip in config["clips"]]
    node_ids = [node["id"] for node in config["graph"]["nodes"]]
    edge_ids = [edge["id"] for edge in config["graph"]["edges"]]
    for kind, identifiers in (
        ("clip", clip_ids),
        ("node", node_ids),
        ("edge", edge_ids),
    ):
        if len(identifiers) != len(set(identifiers)):
            raise ValueError(f"duplicate {kind} identifier in build config")


def apply_overrides(config: dict[str, Any], args: argparse.Namespace) -> None:
    if args.package_version_override:
        config["package"]["version"] = args.package_version_override
    if args.created_at_override:
        config["package"]["createdAt"] = args.created_at_override
    if args.walk_speed_override is None:
        return
    if args.walk_speed_override <= 0:
        raise ValueError("walk speed override must be positive")

    previous = float(config["calibration"]["walkAveragePtPerSecond"])
    replacement = float(args.walk_speed_override)
    config["calibration"]["walkAveragePtPerSecond"] = replacement
    run_speed = float(config["calibration"]["runAveragePtPerSecond"])
    config["calibration"]["runToWalkSpeedRatio"] = round(
        run_speed / replacement,
        6,
    )
    for clip in config["clips"]:
        motion = clip["motion"]
        for key in (
            "speedPtPerSecond",
            "startSpeedPtPerSecond",
            "endSpeedPtPerSecond",
        ):
            if key in motion and math.isclose(float(motion[key]), previous):
                motion[key] = replacement


def main() -> None:
    args = parse_args()
    repo_root = args.repo_root.resolve(strict=True)
    config_path = args.config.resolve(strict=True)
    config = load_config(repo_root, config_path)
    apply_overrides(config, args)
    validate_config(config)
    output = args.output.resolve(strict=False)
    output.parent.mkdir(parents=True, exist_ok=True)

    source_canvas = tuple(int(value) for value in config["sourceCanvasPx"])
    runtime_canvas = tuple(int(value) for value in config["runtimeCanvasPx"])
    if len(source_canvas) != 2 or len(runtime_canvas) != 2:
        raise ValueError("canvas dimensions must contain width and height")
    scale_y = runtime_canvas[1] / source_canvas[1]
    ground_y = float(config["sourceGroundYExclusivePx"]) * scale_y
    compilation_canvas_value = config.get("compilationCanvasPx")
    compilation_canvas = (
        tuple(int(value) for value in compilation_canvas_value)
        if compilation_canvas_value is not None
        else None
    )
    if compilation_canvas is not None and len(compilation_canvas) != 2:
        raise ValueError("compilationCanvasPx must contain two dimensions")
    source_placement = tuple(int(value) for value in config.get("sourcePlacementPx", [0, 0]))
    if len(source_placement) != 2:
        raise ValueError("sourcePlacementPx must contain two values")

    temporary = Path(
        tempfile.mkdtemp(prefix=f"{output.name}.build-", dir=output.parent)
    )
    try:
        summaries = [
            compile_clip(
                repo_root,
                temporary,
                clip,
                source_canvas,
                runtime_canvas,
                ground_y,
                compilation_canvas,
                source_placement,
            )
            for clip in config["clips"]
        ]

        package_manifest = {
            "schemaVersion": SCHEMA_VERSION,
            "package": config["package"],
            "pet": config["pet"],
            "art": {
                "canvasPx": list(runtime_canvas),
                "baseHeightPt": config["baseHeightPt"],
                "coordinateOrigin": "top-left",
                "defaultNode": config["defaultNode"],
                "groundYPx": round(ground_y, 3),
            },
            "renderAssets": {
                "mode": "frames",
                "pixelFormat": "rgba8-straight",
            },
            "graph": "graph.json",
            "reviewIndex": "reviews/index.json",
            "integrity": "integrity.json",
        }
        write_json(temporary / "package.json", package_manifest)
        write_json(
            temporary / "graph.json",
            {
                "schemaVersion": SCHEMA_VERSION,
                "nodes": config["graph"]["nodes"],
                "edges": config["graph"]["edges"],
            },
        )
        write_json(
            temporary / "demo-sequence.json",
            {
                "schemaVersion": SCHEMA_VERSION,
                "id": config["demoSequence"]["id"],
                "segments": config["demoSequence"]["segments"],
            },
        )
        write_json(
            temporary / "reviews" / "index.json",
            {
                "schemaVersion": SCHEMA_VERSION,
                "runtimeChainStatus": config.get("runtimeReview", {}).get(
                    "packageStatus",
                    "awaiting-human-runtime-review",
                ),
                "installable": bool(
                    config.get("runtimeReview", {}).get("installable", False)
                ),
                "approvedRuntimeChains": config.get("runtimeReview", {}).get(
                    "approvedRuntimeChains",
                    [],
                ),
                "remainingRuntimeGates": config.get("runtimeReview", {}).get(
                    "remainingGates",
                    [],
                ),
                "materialUnits": config["materialUnits"],
                "rootMotion": {
                    "status": config["calibration"].get(
                        "status",
                        "provisional-calibrated-awaiting-runtime-review",
                    ),
                    "walkAveragePtPerSecond": config["calibration"]["walkAveragePtPerSecond"],
                    "runAveragePtPerSecond": config["calibration"]["runAveragePtPerSecond"],
                    "method": "per-frame cumulative samples compiled from clip-specific calibrated motion profiles",
                    "mechanicalLimit": "calibration and tests do not replace human desktop review of paw contact and window motion",
                },
                "normalization": config.get("normalization"),
                "graphConnectivity": config.get("graphConnectivity"),
            },
        )
        write_json(temporary / "integrity.json", integrity_manifest(temporary))
        assert_no_hidden_flags(temporary)
        backup = install_build(temporary, output, config["package"]["createdAt"])
    except Exception:
        if temporary.exists():
            shutil.rmtree(temporary)
        raise

    total_motion = sum(summary["rootMotionEndPt"] for summary in summaries)
    print(
        json.dumps(
            {
                "output": str(output),
                "backup": str(backup) if backup else None,
                "clips": summaries,
                "allClipTerminalMotionPt": round(total_motion, 6),
                "integrityFiles": len(read_json(output / "integrity.json")["files"]),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
