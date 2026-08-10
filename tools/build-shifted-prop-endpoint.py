#!/usr/bin/env python3
"""Build a strict Seedance endpoint with a fixed prop shifted on one safe canvas."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "workspaces/wubai-private/actions/side-curled-left-to-sit-front/v1/qa/process_candidate.py"
SPEC = importlib.util.spec_from_file_location("petsgraph_cyan_key", BASE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load cyan key helper: {BASE}")
CYAN_KEY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CYAN_KEY)


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
    parser.add_argument("--pet", type=Path, required=True)
    parser.add_argument("--prop", type=Path, required=True)
    parser.add_argument("--prop-offset", type=int, nargs=2, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()

    pet_path = resolve(args.pet, strict=True)
    prop_path = resolve(args.prop, strict=True)
    output = resolve(args.output, strict=False)
    manifest = resolve(args.manifest, strict=False)
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest.parent.mkdir(parents=True, exist_ok=True)

    pet = CYAN_KEY.key_cyan(Image.open(pet_path)).convert("RGBA")
    prop = Image.open(prop_path).convert("RGBA")
    if pet.size != prop.size:
        raise ValueError("pet and prop references must share one safe canvas")
    shifted_prop = Image.new("RGBA", pet.size, (0, 0, 0, 0))
    shifted_prop.alpha_composite(prop, tuple(args.prop_offset))
    composite = Image.new("RGBA", pet.size, (0, 255, 255, 255))
    composite.alpha_composite(shifted_prop)
    composite.alpha_composite(pet)
    composite.convert("RGB").save(output, optimize=True)

    evidence = {
        "schema": 1,
        "purpose": "strict Seedance endpoint reference only",
        "petSourceModified": False,
        "propSourceModified": False,
        "operation": "fixed cyan key plus one fixed prop translation and alpha composition",
        "pet": {"path": pet_path.relative_to(ROOT).as_posix(), "sha256": sha256(pet_path)},
        "prop": {"path": prop_path.relative_to(ROOT).as_posix(), "sha256": sha256(prop_path)},
        "propOffsetPx": args.prop_offset,
        "output": {"path": output.relative_to(ROOT).as_posix(), "sha256": sha256(output)},
    }
    manifest.write_text(
        json.dumps(evidence, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(evidence["output"], ensure_ascii=False))


if __name__ == "__main__":
    main()
