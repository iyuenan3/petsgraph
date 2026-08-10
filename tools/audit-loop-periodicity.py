#!/usr/bin/env python3
"""Measure compiled loop motion and seam energy without judging visual quality."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]


def resolve(path: Path) -> Path:
    value = path if path.is_absolute() else ROOT / path
    value = value.resolve(strict=True)
    value.relative_to(ROOT)
    return value


def premultiplied(path: Path) -> np.ndarray:
    value = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32) / 255
    value[..., :3] *= value[..., 3:4]
    return value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    package = resolve(args.package)
    output = args.output if args.output.is_absolute() else ROOT / args.output
    output = output.resolve(strict=False)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.parent.relative_to(ROOT)
    if output.exists():
        raise FileExistsError(f"refusing to overwrite {output}")

    graph = json.loads((package / "graph.json").read_text(encoding="utf-8"))
    nodes = [
        node
        for node in graph["nodes"]
        if node.get("role") in ("dwell", "gateway")
    ]
    results = []
    for node in nodes:
        clip_id = node["loopClip"]
        clip = json.loads(
            (package / "clips" / f"{clip_id}.json").read_text(encoding="utf-8")
        )
        images = [premultiplied(package / frame["src"]) for frame in clip["frames"]]
        adjacent = np.asarray(
            [np.abs(images[index] - images[index - 1]).mean() for index in range(1, len(images))]
        )
        seam = float(np.abs(images[0] - images[-1]).mean())
        excursion = max(float(np.abs(image - images[0]).mean()) for image in images)
        median = float(np.median(adjacent)) if len(adjacent) else 0.0
        results.append(
            {
                "node": node["id"],
                "role": node.get("role"),
                "scene": node.get("scene"),
                "clip": clip_id,
                "frames": len(images),
                "durationSeconds": len(images) * float(clip["frames"][0]["durationMs"]) / 1000,
                "adjacentPremultipliedMAD": {
                    "median": median,
                    "p95": float(np.percentile(adjacent, 95)) if len(adjacent) else 0.0,
                    "maximum": float(adjacent.max()) if len(adjacent) else 0.0,
                },
                "seamPremultipliedMAD": seam,
                "seamToAdjacentMedianRatio": seam / median if median > 0 else None,
                "maximumExcursionFromFirstFrame": excursion,
                "mechanicalLimit": "low seam energy cannot prove that repeated motion feels natural",
            }
        )

    report = {
        "schema": 1,
        "package": package.relative_to(ROOT).as_posix(),
        "status": "mechanical-loop-periodicity-audit-requires-visual-judgment",
        "loops": results,
    }
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
