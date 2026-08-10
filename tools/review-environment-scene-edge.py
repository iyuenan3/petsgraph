#!/usr/bin/env python3
"""Render one unmodified scene edge over a fixed environment prop."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]


def resolve(path: Path, *, strict: bool) -> Path:
    value = path if path.is_absolute() else ROOT / path
    value = value.resolve(strict=strict)
    value.relative_to(ROOT)
    return value


def sequence(path: Path) -> list[Path]:
    values = sorted(path.glob("frame-*.png"))
    expected = [f"frame-{index:03d}.png" for index in range(len(values))]
    if not values or [value.name for value in values] != expected:
        raise ValueError(f"{path} is not a contiguous zero-based PNG sequence")
    return values


def smoothstep(value: float) -> float:
    value = min(1.0, max(0.0, value))
    return 3 * value * value - 2 * value * value * value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", type=Path, required=True)
    parser.add_argument("--prop", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--direction", choices=["left", "right"], required=True)
    parser.add_argument("--motion-source-px", type=int, default=152)
    parser.add_argument(
        "--prop-crop",
        type=int,
        nargs=4,
        default=[0, 144, 960, 784],
        metavar=("LEFT", "TOP", "RIGHT", "BOTTOM"),
    )
    parser.add_argument("--motion-start-frame", type=int, required=True)
    parser.add_argument("--motion-end-frame", type=int, required=True)
    parser.add_argument(
        "--prop-visibility",
        choices=["throughout", "target-only", "none"],
        default="throughout",
    )
    args = parser.parse_args()

    source_root = resolve(args.frames, strict=True)
    prop_path = resolve(args.prop, strict=True)
    output = resolve(args.output, strict=False)
    if output.exists():
        raise RuntimeError(f"refusing to overwrite {output}")
    output.mkdir(parents=True)
    review_root = output / "review-frames"
    review_root.mkdir()

    sources = sequence(source_root)
    if not 0 <= args.motion_start_frame < args.motion_end_frame < len(sources):
        raise ValueError("motion frame window must fit inside the source sequence")
    source_size = Image.open(sources[0]).size
    if any(Image.open(source).size != source_size for source in sources):
        raise ValueError("all source frames must share one canvas")
    prop_crop = tuple(args.prop_crop)
    prop = None
    if args.prop_visibility != "none":
        prop = Image.open(prop_path).convert("RGBA").crop(prop_crop)
        if prop.size != source_size:
            raise ValueError(f"prop crop {prop.size} must match source frame {source_size}")
    canvas_size = (source_size[0] + args.motion_source_px, source_size[1])
    prop_x = args.motion_source_px

    for index, source in enumerate(sources):
        u = smoothstep(
            (index - args.motion_start_frame)
            / (args.motion_end_frame - args.motion_start_frame)
        )
        if args.direction == "left":
            pet_x = round(args.motion_source_px * (1 - u))
        else:
            pet_x = round(args.motion_source_px * u)
        canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
        if args.prop_visibility == "throughout" or (
            args.prop_visibility == "target-only" and index == len(sources) - 1
        ):
            assert prop is not None
            canvas.alpha_composite(prop, (prop_x, 0))
        canvas.alpha_composite(Image.open(source).convert("RGBA"), (pet_x, 0))
        canvas.save(review_root / f"frame-{index:03d}.png", optimize=True)

    previews = output / "previews"
    previews.mkdir()
    for fps, name in ((24, "normal"), (12, "2x-slow")):
        subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-framerate", str(fps), "-i", str(review_root / "frame-%03d.png"),
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
                str(previews / f"environment-edge-{name}.mp4"),
            ],
            check=True,
        )

    selected = list(range(0, len(sources), 8))
    if selected[-1] != len(sources) - 1:
        selected.append(len(sources) - 1)
    columns = 6
    cell = (320, max(200, round(320 * canvas_size[1] / canvas_size[0])))
    sheet = Image.new(
        "RGB",
        (columns * cell[0], math.ceil(len(selected) / columns) * cell[1]),
        (29, 32, 37),
    )
    draw = ImageDraw.Draw(sheet)
    for position, index in enumerate(selected):
        image = Image.open(review_root / f"frame-{index:03d}.png").convert("RGBA")
        image.thumbnail((cell[0] - 8, cell[1] - 24), Image.Resampling.LANCZOS)
        column = position % columns
        row = position // columns
        x = column * cell[0] + (cell[0] - image.width) // 2
        y = row * cell[1] + 20
        sheet.paste(image.convert("RGB"), (x, y))
        draw.text((column * cell[0] + 5, row * cell[1] + 4), f"frame {index:03d}", fill="white")
    sheet.save(output / "contact-dark-every8f.jpg", quality=92)

    manifest = {
        "schema": 1,
        "status": "mechanical-preview-pending-visual-review",
        "sourceFramesModified": False,
        "environmentPropFixed": args.prop_visibility != "none",
        "environmentPropVisibleThroughout": args.prop_visibility == "throughout",
        "environmentPropVisibility": args.prop_visibility,
        "direction": args.direction,
        "motionSourcePx": args.motion_source_px,
        "motionStartFrame": args.motion_start_frame,
        "motionEndFrame": args.motion_end_frame,
        "sourceCanvas": list(source_size),
        "reviewCanvas": list(canvas_size),
        "propCrop": list(prop_crop),
        "frames": len(sources),
        "source": source_root.relative_to(ROOT).as_posix(),
        "prop": prop_path.relative_to(ROOT).as_posix(),
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == "__main__":
    main()
