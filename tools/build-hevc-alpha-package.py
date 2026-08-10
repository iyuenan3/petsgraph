#!/usr/bin/env python3
"""Compile an immutable PNG frame package into a derived HEVC Alpha package."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
from typing import Any
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_VERSION = "0.3.0"


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


def ordered_sequence_digest(frames: list[Path]) -> str:
    digest = hashlib.sha256()
    for frame in frames:
        digest.update(frame.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(sha256(frame).encode("ascii"))
        digest.update(b"\n")
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


def compile_encoder(output: Path) -> None:
    environment = os.environ.copy()
    environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    environment.setdefault("CLANG_MODULE_CACHE_PATH", "/tmp/petsgraph-hevc-clang-cache")
    Path(environment["CLANG_MODULE_CACHE_PATH"]).mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "/usr/bin/xcrun",
            "swiftc",
            str(ROOT / "tools" / "encode-hevc-alpha.swift"),
            "-O",
            "-o",
            str(output),
        ],
        cwd=ROOT,
        env=environment,
        check=True,
    )


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


def main() -> None:
    args = parse_args()
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

    temporary = Path(
        tempfile.mkdtemp(prefix=f"{output.name}.build-", dir=output.parent)
    )
    helper_directory = Path(tempfile.mkdtemp(prefix="petsgraph-hevc-encoder-"))
    encoder = helper_directory / "encode-hevc-alpha"
    summaries: list[dict[str, Any]] = []
    try:
        compile_encoder(encoder)
        for filename in ("graph.json", "demo-sequence.json", "behavior.json"):
            copy_json_with_schema(source / filename, temporary / filename)

        review = copy_json_with_schema(
            source / "reviews" / "index.json",
            temporary / "reviews" / "index.json",
        )
        review["runtimeChainStatus"] = "hevc-alpha-experiment-awaiting-human-runtime-review"
        review["installable"] = False
        remaining = list(review.get("remainingRuntimeGates", []))
        gate = "HEVC Alpha full desktop visual quality, loop seam, CPU, memory and stability review"
        if gate not in remaining:
            remaining.append(gate)
        review["remainingRuntimeGates"] = remaining
        write_json(temporary / "reviews" / "index.json", review)

        props = source_manifest.get("renderAssets", {}).get("environmentProps", [])
        for prop in props:
            prop_source = safe_child(source, str(prop["src"]), strict=True)
            prop_destination = safe_child(temporary, str(prop["src"]), strict=False)
            prop_destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(prop_source, prop_destination)

        clips_directory = source / "clips"
        clip_paths = sorted(clips_directory.glob("*.json"))
        if len(clip_paths) != 53:
            raise ValueError(f"expected 53 source clips, found {len(clip_paths)}")
        for clip_path in clip_paths:
            clip = read_json(clip_path)
            clip_id = str(clip["id"])
            frames = clip.get("frames", [])
            frame_paths = [
                safe_child(source, str(frame["src"]), strict=True)
                for frame in frames
            ]
            if len(frame_paths) != len(frames) or not frame_paths:
                raise ValueError(f"clip {clip_id} has an invalid frame list")
            for frame_path in frame_paths:
                validate_regular_file(frame_path)
            expected_names = [f"{index:04d}.png" for index in range(len(frames))]
            if [path.name for path in frame_paths] != expected_names:
                raise ValueError(f"clip {clip_id} frames are not contiguous and ordered")
            source_digest = str(
                clip.get("provenance", {}).get("sourceSequenceDigest", "")
            )
            if len(source_digest) != 64:
                raise ValueError(f"clip {clip_id} lacks its approved source digest")
            compiled_digest = ordered_sequence_digest(frame_paths)
            media_relative = f"media/{clip_id}.mov"
            media_path = temporary / media_relative
            media_path.parent.mkdir(parents=True, exist_ok=True)
            encoded = subprocess.run(
                [str(encoder), str(frame_paths[0].parent), str(media_path), "24"],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            encode_report = json.loads(encoded.stdout)
            if int(encode_report["frameCount"]) != len(frames):
                raise ValueError(f"clip {clip_id} encoder frame count mismatch")
            clip["schemaVersion"] = SCHEMA_VERSION
            clip["media"] = {
                "type": "video",
                "src": media_relative,
                "codec": "hevc-alpha",
                "container": "quicktime",
                "frameCount": len(frames),
                "frameRate": 24.0,
                "alphaMode": "premultiplied",
                "colorSpace": "sRGB",
                "sourceSequenceDigest": source_digest,
                "compiledFrameSequenceDigest": compiled_digest,
            }
            write_json(temporary / "clips" / clip_path.name, clip)
            summaries.append(
                {
                    "id": clip_id,
                    "frames": len(frames),
                    "pngBytes": sum(path.stat().st_size for path in frame_paths),
                    "hevcBytes": media_path.stat().st_size,
                    "encodeSeconds": float(encode_report["encodeSeconds"]),
                    "compiledFrameSequenceDigest": compiled_digest,
                }
            )

        manifest = source_manifest
        manifest["schemaVersion"] = SCHEMA_VERSION
        manifest["package"]["version"] = args.version
        manifest["package"]["createdAt"] = datetime.now(
            ZoneInfo("Asia/Shanghai")
        ).strftime("%Y-%m-%dT%H:%M:%S%z")
        manifest["renderAssets"]["mode"] = "hevc-alpha-clips"
        manifest["renderAssets"]["pixelFormat"] = "bgra8-premultiplied"
        manifest["sourceAssets"] = "source-assets.json"
        write_json(temporary / "package.json", manifest)

        source_record = {
            "schemaVersion": SCHEMA_VERSION,
            "sourcePackage": {
                "id": source_manifest["package"]["id"],
                "version": read_json(source_manifest_path)["package"]["version"],
                "manifestSha256": sha256(source_manifest_path),
                "integritySha256": sha256(source / "integrity.json"),
                "renderMode": "frames",
                "retainedExternally": True,
            },
            "derivation": {
                "codec": "AVVideoCodecTypeHEVCWithAlpha",
                "container": "quicktime",
                "frameRate": 24,
                "frameOrder": "unchanged",
                "spatialTransform": "none",
                "temporalTransform": "none",
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
    finally:
        shutil.rmtree(helper_directory, ignore_errors=True)

    total_png = sum(item["pngBytes"] for item in summaries)
    total_hevc = sum(item["hevcBytes"] for item in summaries)
    print(
        json.dumps(
            {
                "output": str(output),
                "clips": len(summaries),
                "frames": sum(item["frames"] for item in summaries),
                "pngBytes": total_png,
                "hevcBytes": total_hevc,
                "hevcToPngRatio": total_hevc / total_png,
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
