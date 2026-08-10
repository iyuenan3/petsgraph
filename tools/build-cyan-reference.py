#!/usr/bin/env python3
"""Composite one approved transparent endpoint over the Seedance cyan key color."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CYAN = (0, 255, 255, 255)


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
    parser.add_argument("--underlay", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()

    source = resolve(args.source, strict=True)
    underlay = resolve(args.underlay, strict=True) if args.underlay else None
    output = resolve(args.output, strict=False)
    manifest = resolve(args.manifest, strict=False)
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest.parent.mkdir(parents=True, exist_ok=True)

    foreground = Image.open(source).convert("RGBA")
    background = Image.new("RGBA", foreground.size, CYAN)
    if underlay is not None:
        underlay_image = Image.open(underlay).convert("RGBA")
        if underlay_image.size != foreground.size:
            raise ValueError("underlay and source must share one canvas")
        background.alpha_composite(underlay_image)
    background.alpha_composite(foreground)
    background.convert("RGB").save(output, optimize=True)

    evidence = {
        "schema": 1,
        "purpose": "Seedance strict endpoint reference only; not a runtime material source",
        "sourceFramesModified": False,
        "interpolation": False,
        "operation": "alpha composite source over opaque RGB(0,255,255) canvas at original coordinates",
        "source": {
            "path": source.relative_to(ROOT).as_posix(),
            "sha256": sha256(source),
            "size": list(foreground.size),
        },
        "underlay": (
            {
                "path": underlay.relative_to(ROOT).as_posix(),
                "sha256": sha256(underlay),
            }
            if underlay is not None
            else None
        ),
        "output": {
            "path": output.relative_to(ROOT).as_posix(),
            "sha256": sha256(output),
            "size": list(foreground.size),
        },
    }
    manifest.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence["output"], ensure_ascii=False))


if __name__ == "__main__":
    main()
