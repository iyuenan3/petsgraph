#!/usr/bin/env python3
"""Compile an immutable PNG fact package into fixed-crop premultiplied RGBA media."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import stat
import tempfile
from typing import Any
from zoneinfo import ZoneInfo

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_VERSION = "0.4.0"
PADDING_PX = 4


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-package", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--padding", type=int, default=PADDING_PX)
    parser.add_argument(
        "--base-height-pt",
        type=float,
        help=(
            "candidate-only presentation height override; changes package display "
            "metadata without changing source frames"
        ),
    )
    parser.add_argument(
        "--release-approved",
        action="store_true",
        help=(
            "promote a derivative of an already installable source package to "
            "runtime-chain-approved; otherwise keep it as a review candidate"
        ),
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


def safe_child(root: Path, relative: str, *, strict: bool) -> Path:
    candidate_path = Path(relative)
    if not relative or candidate_path.is_absolute() or any(
        part in ("", ".", "..") for part in candidate_path.parts
    ):
        raise ValueError(f"unsafe package path: {relative}")
    candidate = (root / candidate_path).resolve(strict=strict)
    candidate.relative_to(root)
    return candidate


def is_hidden(path: Path) -> bool:
    hidden_mask = getattr(stat, "UF_HIDDEN", 0)
    return path.name.startswith(".") or bool(path.lstat().st_flags & hidden_mask)


def validate_regular_file(path: Path) -> None:
    if is_hidden(path) or not path.is_file() or path.is_symlink():
        raise ValueError(f"required package file is hidden or not regular: {path}")


def verify_source_integrity(source: Path) -> dict[str, Any]:
    integrity_path = source / "integrity.json"
    validate_regular_file(integrity_path)
    integrity = read_json(integrity_path)
    if integrity.get("algorithm", "").lower() != "sha256":
        raise ValueError("source package does not use SHA-256 integrity")
    seen: set[str] = set()
    for entry in integrity.get("files", []):
        relative = str(entry["path"])
        if relative in seen:
            raise ValueError(f"duplicate source integrity entry: {relative}")
        seen.add(relative)
        path = safe_child(source, relative, strict=True)
        validate_regular_file(path)
        if path.stat().st_size != int(entry["bytes"]):
            raise ValueError(f"source byte count mismatch: {relative}")
        if sha256(path) != str(entry["sha256"]).lower():
            raise ValueError(f"source SHA-256 mismatch: {relative}")
    return integrity


def copy_json_with_schema(source: Path, destination: Path) -> dict[str, Any]:
    payload = read_json(source)
    payload["schemaVersion"] = SCHEMA_VERSION
    write_json(destination, payload)
    return payload


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
        "schemaVersion": SCHEMA_VERSION,
        "algorithm": "sha256",
        "files": files,
    }


def fixed_alpha_crop(
    frame_paths: list[Path], canvas: tuple[int, int], padding: int
) -> tuple[int, int, int, int]:
    union: tuple[int, int, int, int] | None = None
    for path in frame_paths:
        with Image.open(path) as image:
            rgba = image.convert("RGBA")
            if rgba.size != canvas:
                raise ValueError(f"frame canvas mismatch: {path}")
            bounds = rgba.getchannel("A").getbbox()
        if bounds is None:
            continue
        if union is None:
            union = bounds
        else:
            union = (
                min(union[0], bounds[0]),
                min(union[1], bounds[1]),
                max(union[2], bounds[2]),
                max(union[3], bounds[3]),
            )
    if union is None:
        raise ValueError("clip contains no visible pixels")
    left = max(0, union[0] - padding)
    top = max(0, union[1] - padding)
    right = min(canvas[0], union[2] + padding)
    bottom = min(canvas[1], union[3] + padding)
    return left, top, right - left, bottom - top


def compile_clip(
    frame_paths: list[Path], output: Path, crop: tuple[int, int, int, int]
) -> str:
    left, top, width, height = crop
    crop_box = (left, top, left + width, top + height)
    digest = hashlib.sha256()
    with output.open("wb") as destination:
        for path in frame_paths:
            with Image.open(path) as image:
                cropped = image.convert("RGBA").crop(crop_box)
                red, green, blue, alpha = cropped.split()
                premultiplied = Image.merge(
                    "RGBA",
                    (
                        ImageChops.multiply(red, alpha),
                        ImageChops.multiply(green, alpha),
                        ImageChops.multiply(blue, alpha),
                        alpha,
                    ),
                )
                raw = premultiplied.tobytes("raw", "RGBA")
            destination.write(raw)
            digest.update(raw)
    return digest.hexdigest()


def required_clip_ids(graph: dict[str, Any]) -> set[str]:
    return {
        str(value)
        for value in (
            [node["loopClip"] for node in graph.get("nodes", [])]
            + [edge["clip"] for edge in graph.get("edges", [])]
        )
    }


def main() -> None:
    args = parse_args()
    if args.base_height_pt is not None and args.base_height_pt <= 0:
        raise ValueError("--base-height-pt must be positive")
    if args.release_approved and args.base_height_pt is not None:
        raise ValueError(
            "a presentation height override requires fresh runtime review before release approval"
        )
    if args.padding < 0:
        raise ValueError("--padding must be non-negative")
    source = within_repo(args.source_package, strict=True)
    output = within_repo(args.output, strict=False)
    if source.suffix != ".petsgraph-pet" or not source.is_dir():
        raise ValueError("--source-package must be a package directory")
    if output.suffix != ".petsgraph-pet":
        raise ValueError("--output must end in .petsgraph-pet")
    if output.exists():
        raise FileExistsError(f"refusing to overwrite derived package: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)

    source_integrity = verify_source_integrity(source)
    source_manifest_path = source / "package.json"
    source_manifest = read_json(source_manifest_path)
    if source_manifest.get("renderAssets", {}).get("mode") != "frames":
        raise ValueError("source package must use frame rendering")
    canvas_values = source_manifest.get("art", {}).get("canvasPx", [])
    if len(canvas_values) != 2 or min(canvas_values) <= 0:
        raise ValueError("source package has an invalid canvas")
    canvas = int(canvas_values[0]), int(canvas_values[1])

    source_review_path = safe_child(
        source,
        str(source_manifest.get("reviewIndex", "")),
        strict=True,
    )
    validate_regular_file(source_review_path)
    source_review = read_json(source_review_path)
    if args.release_approved:
        if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version) is None:
            raise ValueError("release-approved package version must be semantic")
        if not source_review.get("installable"):
            raise ValueError("release-approved derivative requires an installable source")
        if source_review.get("runtimeChainStatus") != "runtime-chain-approved":
            raise ValueError(
                "release-approved derivative requires a runtime-chain-approved source"
            )

    temporary = Path(tempfile.mkdtemp(prefix=f"{output.name}.build-", dir=output.parent))
    summaries: list[dict[str, Any]] = []
    try:
        graph = copy_json_with_schema(source / "graph.json", temporary / "graph.json")
        for filename in ("demo-sequence.json", "behavior.json"):
            copy_json_with_schema(source / filename, temporary / filename)

        review = copy_json_with_schema(
            source_review_path,
            temporary / "reviews" / "index.json",
        )
        if args.release_approved:
            review["runtimeChainStatus"] = "runtime-chain-approved"
            review["installable"] = True
            approved_chains = list(review.get("approvedRuntimeChains", []))
            approved_chain = f"wubai-quiet-companion-{args.version}"
            if approved_chain not in approved_chains:
                approved_chains.append(approved_chain)
            review["approvedRuntimeChains"] = approved_chains
            review["remainingRuntimeGates"] = []
        else:
            review["runtimeChainStatus"] = "cropped-rgba-awaiting-human-runtime-review"
            review["installable"] = False
            remaining = list(review.get("remainingRuntimeGates", []))
            gate = (
                "fixed-crop RGBA full desktop visual quality, CPU, memory and "
                "stability review"
            )
            if gate not in remaining:
                remaining.append(gate)
            review["remainingRuntimeGates"] = remaining
        write_json(temporary / "reviews" / "index.json", review)

        for prop in source_manifest.get("renderAssets", {}).get("environmentProps", []):
            prop_source = safe_child(source, str(prop["src"]), strict=True)
            prop_destination = safe_child(temporary, str(prop["src"]), strict=False)
            prop_destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(prop_source, prop_destination)

        clip_paths = sorted((source / "clips").glob("*.json"))
        actual_ids = {path.stem for path in clip_paths}
        expected_ids = required_clip_ids(graph)
        if actual_ids != expected_ids:
            raise ValueError("source clips do not exactly match graph references")
        for clip_path in clip_paths:
            clip = read_json(clip_path)
            clip_id = str(clip["id"])
            if clip_id != clip_path.stem:
                raise ValueError(f"clip id mismatch: {clip_path.name}")
            frames = clip.get("frames", [])
            frame_paths = [
                safe_child(source, str(frame["src"]), strict=True) for frame in frames
            ]
            if not frame_paths:
                raise ValueError(f"clip {clip_id} has no frames")
            frame_durations = [float(frame["durationMs"]) for frame in frames]
            if (
                min(frame_durations) <= 0
                or max(frame_durations) - min(frame_durations) > 0.001
            ):
                raise ValueError(
                    f"clip {clip_id} must use one fixed authored frame duration"
                )
            frame_rate = 1_000.0 / frame_durations[0]
            if [path.name for path in frame_paths] != [
                f"{index:04d}.png" for index in range(len(frame_paths))
            ]:
                raise ValueError(f"clip {clip_id} frames are not contiguous and ordered")
            for frame_path in frame_paths:
                validate_regular_file(frame_path)
            source_digest = str(
                clip.get("provenance", {}).get("sourceSequenceDigest", "")
            )
            if len(source_digest) != 64:
                raise ValueError(f"clip {clip_id} lacks its approved source digest")

            crop = fixed_alpha_crop(frame_paths, canvas, args.padding)
            media_relative = f"media/{clip_id}.rgba"
            media_path = temporary / media_relative
            media_path.parent.mkdir(parents=True, exist_ok=True)
            compiled_digest = compile_clip(frame_paths, media_path, crop)
            bytes_per_row = crop[2] * 4
            frame_byte_count = bytes_per_row * crop[3]
            expected_bytes = len(frames) * frame_byte_count
            if media_path.stat().st_size != expected_bytes:
                raise ValueError(f"clip {clip_id} raw byte count mismatch")

            clip["schemaVersion"] = SCHEMA_VERSION
            for frame in frames:
                frame["src"] = media_relative
            clip["media"] = {
                "type": "raw-frames",
                "src": media_relative,
                "codec": "raw-rgba8",
                "container": "contiguous-frame-stream",
                "frameCount": len(frames),
                "frameRate": frame_rate,
                "alphaMode": "premultiplied-last",
                "colorSpace": "sRGB",
                "sourceSequenceDigest": source_digest,
                "compiledFrameSequenceDigest": compiled_digest,
                "cropRectPx": list(crop),
                "bytesPerRow": bytes_per_row,
                "frameByteCount": frame_byte_count,
            }
            write_json(temporary / "clips" / clip_path.name, clip)
            summaries.append(
                {
                    "id": clip_id,
                    "frames": len(frames),
                    "authoredFrameRate": frame_rate,
                    "cropRectPx": list(crop),
                    "pngBytes": sum(path.stat().st_size for path in frame_paths),
                    "rgbaBytes": media_path.stat().st_size,
                    "compiledFrameSequenceDigest": compiled_digest,
                }
            )

        manifest = read_json(source_manifest_path)
        manifest["schemaVersion"] = SCHEMA_VERSION
        manifest["package"]["version"] = args.version
        manifest["package"]["createdAt"] = datetime.now(
            ZoneInfo("Asia/Shanghai")
        ).strftime("%Y-%m-%dT%H:%M:%S%z")
        manifest["renderAssets"]["mode"] = "cropped-rgba-clips"
        manifest["renderAssets"]["pixelFormat"] = "rgba8-premultiplied"
        if args.base_height_pt is not None:
            manifest["art"]["baseHeightPt"] = args.base_height_pt
        manifest["sourceAssets"] = "source-assets.json"
        write_json(temporary / "package.json", manifest)

        source_record = {
            "schemaVersion": SCHEMA_VERSION,
            "sourcePackage": {
                "id": source_manifest["package"]["id"],
                "version": source_manifest["package"]["version"],
                "manifestSha256": sha256(source_manifest_path),
                "integritySha256": sha256(source / "integrity.json"),
                "renderMode": "frames",
                "retainedExternally": True,
            },
            "derivation": {
                "format": "raw-rgba8-premultiplied-last",
                "frameRate": "per-clip authored rate from immutable frame timing",
                "frameOrder": "unchanged",
                "spatialTransform": "one fixed alpha-union crop per clip",
                "cropPaddingPx": args.padding,
                "temporalTransform": "none",
                "presentationBaseHeightPt": manifest["art"]["baseHeightPt"],
            },
            "clips": summaries,
            "verifiedSourceIntegrityEntries": len(source_integrity.get("files", [])),
        }
        write_json(temporary / "source-assets.json", source_record)
        write_json(temporary / "integrity.json", integrity_manifest(temporary))
        temporary.rename(output)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise

    total_png = sum(item["pngBytes"] for item in summaries)
    total_rgba = sum(item["rgbaBytes"] for item in summaries)
    print(
        json.dumps(
            {
                "output": str(output),
                "clips": len(summaries),
                "frames": sum(item["frames"] for item in summaries),
                "pngBytes": total_png,
                "rgbaBytes": total_rgba,
                "rgbaToPngRatio": total_rgba / total_png,
                "packageBytes": sum(
                    path.stat().st_size for path in output.rglob("*") if path.is_file()
                ),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
