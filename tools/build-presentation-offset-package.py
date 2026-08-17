#!/usr/bin/env python3
"""Build a review package with one clip-level transient presentation offset.

The source package and its media stay byte-identical.  Only frame contract
metadata is extended, so the desktop window can compensate for generated
camera drift without scaling, reordering, or re-encoding approved pixels.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import stat
import tempfile
from typing import Any
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-package", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--clip-id", required=True)
    parser.add_argument(
        "--keyframe",
        action="append",
        required=True,
        metavar="FRAME:OFFSET_PX",
        help="repeat to define a piecewise-linear transient X offset",
    )
    return parser.parse_args()


def within_repo(path: Path, *, strict: bool) -> Path:
    result = path if path.is_absolute() else ROOT / path
    result = result.resolve(strict=strict)
    result.relative_to(ROOT)
    return result


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_hidden(path: Path) -> bool:
    hidden_mask = getattr(stat, "UF_HIDDEN", 0)
    return path.name.startswith(".") or bool(path.lstat().st_flags & hidden_mask)


def validate_regular_file(path: Path) -> None:
    if is_hidden(path) or not path.is_file() or path.is_symlink():
        raise ValueError(f"required package file is hidden or not regular: {path}")


def integrity_manifest(build_root: Path) -> dict[str, Any]:
    files = []
    for path in sorted(build_root.rglob("*")):
        if not path.is_file() or path.name == "integrity.json":
            continue
        validate_regular_file(path)
        files.append(
            {
                "path": path.relative_to(build_root).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
        )
    return {
        "schemaVersion": "0.4.0",
        "algorithm": "sha256",
        "files": files,
    }


def verify_integrity(package: Path) -> None:
    manifest = read_json(package / "integrity.json")
    if str(manifest.get("algorithm", "")).lower() != "sha256":
        raise ValueError("source package integrity is not SHA-256")
    for entry in manifest.get("files", []):
        relative = Path(str(entry["path"]))
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"unsafe integrity path: {relative}")
        path = package / relative
        validate_regular_file(path)
        if path.stat().st_size != int(entry["bytes"]):
            raise ValueError(f"source byte count mismatch: {relative}")
        if sha256(path) != str(entry["sha256"]).lower():
            raise ValueError(f"source SHA-256 mismatch: {relative}")


def copy_package_file(source: str, destination: str) -> str:
    source_path = Path(source)
    destination_path = Path(destination)
    if source_path.parent.name == "media":
        os.link(source_path, destination_path)
        return str(destination_path)
    return shutil.copy2(source_path, destination_path)


def parse_keyframes(values: list[str], frame_count: int) -> list[tuple[int, float]]:
    parsed: list[tuple[int, float]] = []
    for value in values:
        frame_text, separator, offset_text = value.partition(":")
        if not separator:
            raise ValueError(f"invalid keyframe: {value}")
        frame = int(frame_text)
        offset = float(offset_text)
        if not math.isfinite(offset):
            raise ValueError(f"non-finite keyframe offset: {value}")
        parsed.append((frame, offset))
    parsed.sort()
    if len({frame for frame, _ in parsed}) != len(parsed):
        raise ValueError("duplicate keyframe index")
    if parsed[0] != (0, 0.0) or parsed[-1] != (frame_count - 1, 0.0):
        raise ValueError("the first and final presentation offsets must be zero")
    if parsed[0][0] < 0 or parsed[-1][0] >= frame_count:
        raise ValueError("keyframe is outside the clip")
    return parsed


def interpolate(keyframes: list[tuple[int, float]], frame_count: int) -> list[float]:
    result: list[float] = []
    segment = 0
    for frame in range(frame_count):
        while segment + 1 < len(keyframes) - 1 and frame > keyframes[segment + 1][0]:
            segment += 1
        left_frame, left_offset = keyframes[segment]
        right_frame, right_offset = keyframes[segment + 1]
        progress = (frame - left_frame) / (right_frame - left_frame)
        offset = left_offset + (right_offset - left_offset) * progress
        result.append(round(offset, 6))
    return result


def main() -> None:
    args = parse_args()
    source = within_repo(args.source_package, strict=True)
    output = within_repo(args.output, strict=False)
    if source.suffix != ".petsgraph-pet" or not source.is_dir():
        raise ValueError("--source-package must be a package directory")
    if output.suffix != ".petsgraph-pet":
        raise ValueError("--output must end in .petsgraph-pet")
    if output.exists():
        raise FileExistsError(f"refusing to overwrite derivative package: {output}")
    verify_integrity(source)

    clip_path = source / "clips" / f"{args.clip_id}.json"
    validate_regular_file(clip_path)
    source_clip = read_json(clip_path)
    frames = source_clip.get("frames", [])
    if not frames:
        raise ValueError(f"clip {args.clip_id} has no frames")
    if source_clip.get("type") != "transition":
        raise ValueError("presentation offsets are review-only transition metadata")
    keyframes = parse_keyframes(args.keyframe, len(frames))
    offsets = interpolate(keyframes, len(frames))
    if max(abs(offsets[index + 1] - offsets[index]) for index in range(len(offsets) - 1)) > 4:
        raise ValueError("presentation offset changes by more than four pixels per frame")

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f"{output.name}.build-", dir=output.parent))
    try:
        shutil.rmtree(temporary)
        shutil.copytree(source, temporary, copy_function=copy_package_file)

        package_manifest = read_json(temporary / "package.json")
        package_manifest["package"]["version"] = args.version
        package_manifest["package"]["createdAt"] = datetime.now(
            ZoneInfo("Asia/Shanghai")
        ).strftime("%Y-%m-%dT%H:%M:%S%z")
        write_json(temporary / "package.json", package_manifest)

        clip = read_json(temporary / "clips" / f"{args.clip_id}.json")
        for frame, offset in zip(clip["frames"], offsets, strict=True):
            frame["presentationOffsetPx"] = [offset, 0.0]
        provenance = clip.setdefault("provenance", {})
        provenance["presentationOffsetStatus"] = (
            "transient-horizontal-review-candidate-source-pixels-unchanged"
        )
        provenance["presentationOffsetKeyframes"] = [
            {"frame": frame, "xPx": offset} for frame, offset in keyframes
        ]
        write_json(temporary / "clips" / f"{args.clip_id}.json", clip)

        review_path = temporary / "reviews" / "index.json"
        review = read_json(review_path)
        review["runtimeChainStatus"] = "presentation-offset-awaiting-human-runtime-review"
        review["installable"] = False
        remaining = list(review.get("remainingRuntimeGates", []))
        gate = "Feiliu floor-to-cat-bed transient motion compensation visual review"
        if gate not in remaining:
            remaining.append(gate)
        review["remainingRuntimeGates"] = remaining
        write_json(review_path, review)

        source_assets_path = temporary / "source-assets.json"
        source_assets = read_json(source_assets_path)
        source_assets.setdefault("derivation", {})["presentationOffset"] = {
            "clipId": args.clip_id,
            "axis": "x",
            "unit": "source-pixel",
            "interpolation": "piecewise-linear",
            "keyframes": [
                {"frame": frame, "xPx": offset} for frame, offset in keyframes
            ],
            "sourcePixelsChanged": False,
            "scaleChanged": False,
            "frameOrderChanged": False,
            "frameTimingChanged": False,
        }
        write_json(source_assets_path, source_assets)

        (temporary / "integrity.json").unlink()
        write_json(temporary / "integrity.json", integrity_manifest(temporary))
        temporary.rename(output)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise

    media_path = output / str(source_clip["media"]["src"])
    source_media_path = source / str(source_clip["media"]["src"])
    print(
        json.dumps(
            {
                "output": str(output),
                "clipId": args.clip_id,
                "frameCount": len(frames),
                "maxOffsetPx": max(offsets),
                "maxDeltaPerFramePx": max(
                    abs(offsets[index + 1] - offsets[index])
                    for index in range(len(offsets) - 1)
                ),
                "sourceMediaSha256": sha256(source_media_path),
                "derivedMediaSha256": sha256(media_path),
                "mediaByteIdentical": source_media_path.read_bytes() == media_path.read_bytes(),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
