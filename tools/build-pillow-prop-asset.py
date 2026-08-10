#!/usr/bin/env python3
"""Normalize one generated pillow-only image into the canonical 960px scene canvas."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve(path: Path, *, strict: bool) -> Path:
    resolved = path if path.is_absolute() else ROOT / path
    resolved = resolved.resolve(strict=strict)
    resolved.relative_to(ROOT)
    return resolved


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument(
        "--target-box",
        type=int,
        nargs=4,
        default=(424, 449, 780, 652),
        metavar=("LEFT", "TOP", "RIGHT", "BOTTOM"),
    )
    args = parser.parse_args()

    source = resolve(args.source, strict=True)
    output = resolve(args.output, strict=False)
    manifest = resolve(args.manifest, strict=False)
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest.parent.mkdir(parents=True, exist_ok=True)

    image = Image.open(source).convert("RGB")
    rgba = Image.new("RGBA", image.size, (0, 0, 0, 0))
    rgba_pixels = []
    for red, green, blue in image.get_flattened_data():
        # The generated reference uses a cyan screen whose red channel remains
        # below the cream pillow. A hard source mask prevents cyan color spill;
        # the single resize below recreates the antialiased output edge.
        chroma_peak = max(green, blue, 1)
        if red > 24 and red / chroma_peak > 0.55:
            rgba_pixels.append((red, green, blue, 255))
        else:
            rgba_pixels.append((0, 0, 0, 0))
    rgba.putdata(rgba_pixels)
    bounds = rgba.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("the generated source has no pillow foreground")
    foreground = rgba.crop(bounds)

    left, top, right, bottom = args.target_box
    if not (0 <= left < right <= 960 and 0 <= top < bottom <= 960):
        raise ValueError("target box must fit inside the canonical 960px canvas")
    normalized = foreground.resize(
        (right - left, bottom - top),
        Image.Resampling.LANCZOS,
    )
    cleaned_pixels = []
    for red, green, blue, alpha in normalized.get_flattened_data():
        if 0 < alpha < 255 and max(green, blue) > red * 1.3:
            ceiling = min(255, round(red * 1.1))
            cleaned_pixels.append((red, min(green, ceiling), min(blue, ceiling), alpha))
        else:
            cleaned_pixels.append((red, green, blue, alpha))
    normalized.putdata(cleaned_pixels)
    canvas = Image.new("RGBA", (960, 960), (0, 0, 0, 0))
    canvas.alpha_composite(normalized, (left, top))
    canvas.save(output, optimize=True)

    evidence = {
        "schema": 1,
        "status": "internal-generated-prop-candidate-awaiting-Maxwell",
        "humanApproved": False,
        "purpose": "static environment prop behind direct-generated whole-pet video frames",
        "source": {
            "path": source.relative_to(ROOT).as_posix(),
            "sha256": sha256(source),
            "canvas": list(image.size),
        },
        "processing": {
            "petPixelsModified": False,
            "sourcePetFramesUsed": False,
            "segmentation": "fixed cream-versus-cyan rule red > 24 and red / max(green, blue) > 0.55",
            "sourceForegroundBounds": list(bounds),
            "targetCanvas": [960, 960],
            "targetBox": [left, top, right, bottom],
            "perFrameRepositioning": False,
            "interpolation": False,
            "crossfade": False,
            "edgeDecontamination": "partial-alpha cyan spill channels capped at 1.1 times red",
        },
        "output": {
            "path": output.relative_to(ROOT).as_posix(),
            "sha256": sha256(output),
        },
    }
    manifest.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence["output"], ensure_ascii=False))


if __name__ == "__main__":
    main()
