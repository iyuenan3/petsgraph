#!/usr/bin/env python3
"""Build deterministic Seedance storyboard references for pillow scene ingress."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CYAN = (0, 255, 255, 255)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def resolve(path: Path, *, strict: bool) -> Path:
    result = path if path.is_absolute() else ROOT / path
    result = result.resolve(strict=strict)
    result.relative_to(ROOT)
    return result


def sha256(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def cyan_composite(*layers: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", layers[0].size, CYAN)
    for layer in layers:
        canvas.alpha_composite(layer.convert("RGBA"))
    return canvas.convert("RGB")


def right_slice(image: Image.Image, left: int) -> Image.Image:
    if not 0 <= left < image.width:
        raise ValueError("slice boundary is outside the reference frame")
    result = Image.new("RGBA", image.size, (0, 0, 0, 0))
    result.alpha_composite(image.crop((left, 0, image.width, image.height)), (left, 0))
    return result


def main() -> None:
    args = parse_args()
    source = resolve(args.source, strict=True)
    output = resolve(args.output, strict=False)
    output.mkdir(parents=True, exist_ok=True)

    selected = {
        "walking": source / "frame-120.png",
        "base": source / "frame-140.png",
        "pillow": source / "frame-155.png",
        "contact": source / "frame-190.png",
    }
    for path in selected.values():
        path.resolve(strict=True).relative_to(ROOT)
    images = {name: Image.open(path).convert("RGBA") for name, path in selected.items()}
    sizes = {image.size for image in images.values()}
    if sizes != {(960, 960)}:
        raise ValueError(f"expected four 960x960 references, got {sorted(sizes)}")

    products = {
        "walking-cyan.png": cyan_composite(images["walking"]),
        "pillow-thin-sliver-cyan.png": cyan_composite(
            images["base"], right_slice(images["pillow"], 900)
        ),
        "pillow-partial-ingress-cyan.png": cyan_composite(
            images["base"], right_slice(images["pillow"], 820)
        ),
        "pillow-contact-cyan.png": cyan_composite(images["contact"]),
    }
    for name, image in products.items():
        destination = output / name
        image.save(destination, optimize=True)
    transparent_target = output / "thin-target-transparent-frames" / "frame-000.png"
    transparent_target.parent.mkdir(parents=True, exist_ok=True)
    thin_transparent = Image.new("RGBA", images["base"].size, (0, 0, 0, 0))
    thin_transparent.alpha_composite(images["base"])
    thin_transparent.alpha_composite(right_slice(images["pillow"], 900))
    thin_transparent.save(transparent_target, optimize=True)
    partial_target = output / "partial-target-transparent-frames" / "frame-000.png"
    partial_target.parent.mkdir(parents=True, exist_ok=True)
    partial_transparent = Image.new("RGBA", images["base"].size, (0, 0, 0, 0))
    partial_transparent.alpha_composite(images["base"])
    partial_transparent.alpha_composite(right_slice(images["pillow"], 820))
    partial_transparent.save(partial_target, optimize=True)

    manifest = {
        "schema": 1,
        "purpose": "Seedance reference storyboard only; not a runtime material source",
        "sourceFramesModified": False,
        "interpolation": False,
        "sources": {
            name: {
                "path": path.relative_to(ROOT).as_posix(),
                "sha256": sha256(path),
            }
            for name, path in selected.items()
        },
        "operations": {
            "walking-cyan.png": "source frame 120 over an opaque cyan background",
            "pillow-thin-sliver-cyan.png": "source frame 140 plus source frame 155 columns 900 through 959",
            "pillow-partial-ingress-cyan.png": "source frame 140 plus source frame 155 columns 820 through 959",
            "pillow-contact-cyan.png": "source frame 190 over an opaque cyan background",
            "thin-target-transparent-frames/frame-000.png": "source frame 140 plus source frame 155 columns 900 through 959 on one transparent canvas",
            "partial-target-transparent-frames/frame-000.png": "source frame 140 plus source frame 155 columns 820 through 959 on one transparent canvas",
        },
        "outputs": {
            name: {
                "path": (output / name).relative_to(ROOT).as_posix(),
                "sha256": sha256(output / name),
            }
            for name in products
        },
    }
    manifest["outputs"]["thin-target-transparent-frames/frame-000.png"] = {
        "path": transparent_target.relative_to(ROOT).as_posix(),
        "sha256": sha256(transparent_target),
    }
    manifest["outputs"]["partial-target-transparent-frames/frame-000.png"] = {
        "path": partial_target.relative_to(ROOT).as_posix(),
        "sha256": sha256(partial_target),
    }
    manifest_path = output / "input-manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        json.dumps(
            {
                "output": output.relative_to(ROOT).as_posix(),
                "manifestSha256": sha256(manifest_path),
                "references": len(products),
                "transparentTargets": 2,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
