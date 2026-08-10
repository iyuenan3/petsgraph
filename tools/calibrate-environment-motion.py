#!/usr/bin/env python3
"""Fit one smooth desktop translation to keep a generated prop over a fixed prop."""

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


def smoothstep(value: float) -> float:
    value = min(1.0, max(0.0, value))
    return 3 * value * value - 2 * value * value * value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", type=Path, required=True)
    parser.add_argument("--prop", type=Path, required=True)
    parser.add_argument("--motion-source-px", type=int, default=152)
    parser.add_argument(
        "--prop-crop",
        type=int,
        nargs=4,
        default=[0, 144, 960, 784],
        metavar=("LEFT", "TOP", "RIGHT", "BOTTOM"),
    )
    parser.add_argument("--sample-step", type=int, default=2)
    parser.add_argument("--search-start", type=int, nargs=3, default=[0, 100, 2])
    parser.add_argument("--search-end", type=int, nargs=3, default=[160, 260, 2])
    args = parser.parse_args()

    source_root = resolve(args.frames)
    prop_path = resolve(args.prop)
    frames = sorted(source_root.glob("frame-*.png"))
    expected = [f"frame-{index:03d}.png" for index in range(len(frames))]
    if not frames or [frame.name for frame in frames] != expected:
        raise ValueError("frames must be a contiguous zero-based sequence")

    first_size = Image.open(frames[0]).size
    prop_crop = tuple(args.prop_crop)
    prop_source = Image.open(prop_path).convert("RGBA").crop(prop_crop)
    if prop_source.size != first_size:
        raise ValueError(
            f"prop crop {prop_source.size} must match source frame {first_size}"
        )

    downsample = 4
    source_size = (
        max(1, round(first_size[0] / downsample)),
        max(1, round(first_size[1] / downsample)),
    )
    distance = round(args.motion_source_px / downsample)
    canvas_size = (source_size[0] + distance, source_size[1])
    prop = prop_source.resize(source_size, Image.Resampling.LANCZOS)
    fixed = np.zeros((canvas_size[1], canvas_size[0]), dtype=np.float32)
    fixed[:, distance : distance + source_size[0]] = (
        np.asarray(prop, dtype=np.float32)[..., 3] / 255
    )
    fixed_weight = max(1.0, float(fixed.sum()))

    sample_indexes = list(range(0, len(frames), args.sample_step))
    source_alpha = []
    for index in sample_indexes:
        image = Image.open(frames[index]).convert("RGBA").resize(
            source_size,
            Image.Resampling.LANCZOS,
        )
        source_alpha.append(np.asarray(image, dtype=np.float32)[..., 3] / 255)

    exposure = np.empty((len(sample_indexes), distance + 1), dtype=np.float32)
    for row, alpha in enumerate(source_alpha):
        for pet_x in range(distance + 1):
            placed = np.zeros_like(fixed)
            placed[:, pet_x : pet_x + source_size[0]] = alpha
            exposure[row, pet_x] = float((fixed * (1 - placed)).sum() / fixed_weight)

    starts = range(*args.search_start)
    ends = range(*args.search_end)
    results = []
    for start in starts:
        for end in ends:
            if start >= end or end >= len(frames):
                continue
            scores = []
            for row, frame_index in enumerate(sample_indexes):
                u = smoothstep((frame_index - start) / (end - start))
                pet_x = round(distance * (1 - u))
                scores.append(float(exposure[row, pet_x]))
            results.append(
                {
                    "startFrame": start,
                    "endFrame": end,
                    "meanExposedPropAlpha": round(float(np.mean(scores)), 8),
                    "p95ExposedPropAlpha": round(float(np.percentile(scores, 95)), 8),
                    "maxExposedPropAlpha": round(float(np.max(scores)), 8),
                }
            )
    results.sort(
        key=lambda item: (
            item["meanExposedPropAlpha"],
            item["p95ExposedPropAlpha"],
            item["maxExposedPropAlpha"],
        )
    )
    print(
        json.dumps(
            {
                "schema": 1,
                "metric": "fixed prop alpha not covered by the unmodified generated pet-and-prop frame",
                "downsample": downsample,
                "sourceCanvas": list(first_size),
                "propCrop": list(prop_crop),
                "sampleStep": args.sample_step,
                "top": results[:10],
                "mechanicalLimit": "coverage fitting does not replace visual review of motion or anatomy",
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
