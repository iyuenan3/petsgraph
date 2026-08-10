#!/usr/bin/env python3
"""Build deterministic QA-only composites of a frame sequence and one shifted prop."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]


def resolve(path: Path, *, strict: bool) -> Path:
    value = path if path.is_absolute() else ROOT / path
    value = value.resolve(strict=strict)
    value.relative_to(ROOT)
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", type=Path, required=True)
    parser.add_argument("--prop", type=Path, required=True)
    parser.add_argument("--prop-offset", type=int, nargs=2, required=True)
    parser.add_argument("--prop-crop", type=int, nargs=4)
    parser.add_argument("--canvas-size", type=int, nargs=2)
    parser.add_argument("--pet-offset", type=int, nargs=2, default=[0, 0])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    source = resolve(args.frames, strict=True)
    prop_path = resolve(args.prop, strict=True)
    output = resolve(args.output, strict=False)
    if output.exists():
        raise RuntimeError(f"refusing to overwrite {output}")
    output.mkdir(parents=True)

    frames = sorted(source.glob("frame-*.png"))
    expected = [f"frame-{index:03d}.png" for index in range(len(frames))]
    if not frames or [frame.name for frame in frames] != expected:
        raise ValueError("source must be a contiguous zero-based frame sequence")
    prop = Image.open(prop_path).convert("RGBA")
    if args.prop_crop is not None:
        prop = prop.crop(tuple(args.prop_crop))
    source_size = Image.open(frames[0]).size
    canvas_size = tuple(args.canvas_size) if args.canvas_size is not None else source_size
    if (
        args.pet_offset[0] < 0
        or args.pet_offset[1] < 0
        or args.pet_offset[0] >= canvas_size[0]
        or args.pet_offset[1] >= canvas_size[1]
    ):
        raise ValueError("pet placement does not intersect the QA canvas")
    shifted = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    shifted.alpha_composite(prop, tuple(args.prop_offset))

    digest = hashlib.sha256()
    for index, source_frame in enumerate(frames):
        pet = Image.open(source_frame).convert("RGBA")
        canvas = shifted.copy()
        canvas.alpha_composite(pet, tuple(args.pet_offset))
        destination = output / f"frame-{index:03d}.png"
        canvas.save(destination, optimize=True)
        digest.update(destination.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(sha256(destination).encode("ascii"))
        digest.update(b"\n")

    manifest = {
        "schema": 1,
        "purpose": "QA-only target-loop composite; not a runtime source",
        "sourceFramesModified": False,
        "operation": "one fixed prop translation and alpha underlay for every frame",
        "source": source.relative_to(ROOT).as_posix(),
        "prop": prop_path.relative_to(ROOT).as_posix(),
        "propOffsetPx": args.prop_offset,
        "propCropPx": args.prop_crop,
        "canvasSizePx": list(canvas_size),
        "petOffsetPx": args.pet_offset,
        "frames": len(frames),
        "orderedSequenceDigest": digest.hexdigest(),
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == "__main__":
    main()
