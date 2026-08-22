from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path
from typing import Any


FIXED_ZIP_TIME = (2026, 1, 1, 0, 0, 0)
JSON_MEDIA_TYPE = "application/json"
RGBA_MEDIA_TYPE = "application/vnd.petsgraph.rgba8"


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def synthetic_rgba(seed: int, frame_count: int) -> bytes:
    result = bytearray()
    for frame in range(frame_count):
        for pixel in range(4):
            alpha = 128 if (frame + pixel + seed) % 3 == 0 else 255
            red = min(alpha, (seed * 31 + frame * 17 + pixel * 23) % 256)
            green = min(alpha, (seed * 13 + frame * 29 + pixel * 19) % 256)
            blue = min(alpha, (seed * 7 + frame * 11 + pixel * 37) % 256)
            result.extend((red, green, blue, alpha))
    return bytes(result)


def build_clip(
    clip_id: str,
    clip_type: str,
    entry_node: str,
    exit_node: str,
    seed: int,
) -> tuple[dict[str, Any], bytes]:
    frame_count = 2 if clip_type == "loop" else 3
    media = synthetic_rgba(seed, frame_count)
    media_path = f"media/{clip_id}/cropped-rgba-clips.rgba"
    clip = {
        "durationSeconds": frame_count / 24,
        "entryNode": entry_node,
        "exitNode": exit_node,
        "formatVersion": "1.0.0",
        "frameCount": frame_count,
        "frameRate": {"denominator": 1, "numerator": 24},
        "geometry": {"cropPx": [0, 0, 2, 2], "presentationOffsetPx": [0, 0]},
        "id": clip_id,
        "playback": {
            "nativeContinuousFrames": True,
            "rate": 1.0,
            "speedProcessing": "none",
        },
        "production": {
            "approvalDigest": sha256(f"synthetic-approval:{clip_id}".encode()),
            "recipeDigest": sha256(f"synthetic-recipe:{clip_id}".encode()),
        },
        "representations": [
            {
                "alpha": "premultiplied",
                "bytes": len(media),
                "bytesPerRow": 8,
                "colorSpace": "srgb",
                "encoding": "raw-premultiplied-rgba8",
                "frameCount": frame_count,
                "frameRate": {"denominator": 1, "numerator": 24},
                "heightPx": 2,
                "id": "cropped-rgba-clips",
                "kind": "cropped-rgba-clips",
                "path": media_path,
                "sha256": sha256(media),
                "widthPx": 2,
            }
        ],
        "safeExitFrames": [0, 1] if clip_type == "loop" else [],
        "stage": {"anchor": "bottom-center", "referenceCanvasPx": [2, 2]},
        "type": clip_type,
    }
    return clip, media


def fixture_entries() -> dict[str, bytes]:
    entries: dict[str, bytes] = {}
    clips = [
        ("rest-primary-loop", "loop", "rest.primary", "rest.primary", 1),
        ("rest-secondary-loop", "loop", "rest.secondary", "rest.secondary", 2),
        (
            "rest-primary-to-rest-secondary",
            "transition",
            "rest.primary",
            "rest.secondary",
            3,
        ),
        (
            "rest-secondary-to-rest-primary",
            "transition",
            "rest.secondary",
            "rest.primary",
            4,
        ),
    ]
    for clip_id, clip_type, entry_node, exit_node, seed in clips:
        clip, media = build_clip(clip_id, clip_type, entry_node, exit_node, seed)
        entries[f"clips/{clip_id}.json"] = canonical_json(clip)
        entries[f"media/{clip_id}/cropped-rgba-clips.rgba"] = media

    entries["manifest.json"] = canonical_json(
        {
            "behavior": "behavior.json",
            "capabilities": {"optional": [], "required": ["cropped-rgba-clips"]},
            "formatVersion": "1.0.0",
            "graph": "graph.json",
            "integrity": "integrity.json",
            "package": {
                "contentVersion": "1.0.0",
                "createdAt": "2026-01-01T00:00:00+08:00",
                "id": "synthetic-cat-v1",
            },
            "pet": {
                "displayName": "Synthetic Cat",
                "id": "synthetic-cat-v1",
                "species": "cat",
            },
            "stage": {
                "anchor": "bottom-center",
                "baseDisplayHeight": 180,
                "defaultNode": "rest.primary",
                "referenceCanvasPx": [2, 2],
            },
        }
    )
    entries["graph.json"] = canonical_json(
        {
            "edges": [
                {
                    "clip": "rest-primary-to-rest-secondary",
                    "from": "rest.primary",
                    "id": "rest-primary-to-rest-secondary",
                    "interruptPolicy": "finish-before-retarget",
                    "to": "rest.secondary",
                },
                {
                    "clip": "rest-secondary-to-rest-primary",
                    "from": "rest.secondary",
                    "id": "rest-secondary-to-rest-primary",
                    "interruptPolicy": "finish-before-retarget",
                    "to": "rest.primary",
                },
            ],
            "formatVersion": "1.0.0",
            "nodes": [
                {
                    "autonomousEligible": True,
                    "id": "rest.primary",
                    "loopClip": "rest-primary-loop",
                    "role": "dwell",
                    "scene": "floor",
                },
                {
                    "autonomousEligible": True,
                    "id": "rest.secondary",
                    "loopClip": "rest-secondary-loop",
                    "role": "dwell",
                    "scene": "floor",
                },
            ],
        }
    )
    entries["behavior.json"] = canonical_json(
        {
            "defaultNode": "rest.primary",
            "formatVersion": "1.0.0",
            "nodeWeights": {"rest.primary": 1.0, "rest.secondary": 1.0},
            "profile": "passive-memorial-companion",
            "sceneWeights": {"floor": 1.0},
            "timing": {
                "avoidImmediateRepeat": True,
                "dwellRangesSeconds": {
                    "rest.primary": [30, 60],
                    "rest.secondary": [45, 90],
                },
                "strategy": "independent-random-dwell",
            },
        }
    )
    integrity_files = []
    for path, data in sorted(entries.items()):
        integrity_files.append(
            {
                "bytes": len(data),
                "mediaType": JSON_MEDIA_TYPE if path.endswith(".json") else RGBA_MEDIA_TYPE,
                "path": path,
                "sha256": sha256(data),
            }
        )
    entries["integrity.json"] = canonical_json(
        {"algorithm": "sha256", "files": integrity_files, "formatVersion": "1.0.0"}
    )
    return entries


def write_fixture(output: Path, *, compression: int = zipfile.ZIP_STORED) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    with zipfile.ZipFile(output, "w", compression=compression, allowZip64=True) as archive:
        for path, data in sorted(fixture_entries().items()):
            info = zipfile.ZipInfo(path, FIXED_ZIP_TIME)
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = compression
            archive.writestr(info, data)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the deterministic synthetic PetPack fixture")
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=Path("petpack/fixtures/synthetic-cat-v1.petpack"),
    )
    parser.add_argument("--deflate", action="store_true", help="use ZIP deflate instead of store")
    args = parser.parse_args()
    write_fixture(args.output, compression=zipfile.ZIP_DEFLATED if args.deflate else zipfile.ZIP_STORED)
    print(f"{sha256(args.output.read_bytes())}  {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
