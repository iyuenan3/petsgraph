#!/usr/bin/env python3
"""Join strict endpoint stages and render a fixed-prop desktop-motion review."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageDraw


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


def frames(path: Path) -> list[Path]:
    values = sorted(path.glob("frame-*.png"))
    expected = [f"frame-{index:03d}.png" for index in range(len(values))]
    if not values or [value.name for value in values] != expected:
        raise ValueError(f"{path} is not a contiguous zero-based PNG sequence")
    return values


def sequence_digest(values: list[Path]) -> str:
    digest = hashlib.sha256()
    for value in values:
        digest.update(value.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(sha256(value).encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def premultiplied_difference(left: Image.Image, right: Image.Image) -> float:
    left_pixels = left.convert("RGBA").get_flattened_data()
    right_pixels = right.convert("RGBA").get_flattened_data()
    total = 0.0
    count = left.width * left.height * 4
    for lhs, rhs in zip(left_pixels, right_pixels, strict=True):
        lhs_alpha = lhs[3] / 255
        rhs_alpha = rhs[3] / 255
        total += abs(lhs[0] * lhs_alpha - rhs[0] * rhs_alpha) / 255
        total += abs(lhs[1] * lhs_alpha - rhs[1] * rhs_alpha) / 255
        total += abs(lhs[2] * lhs_alpha - rhs[2] * rhs_alpha) / 255
        total += abs(lhs[3] - rhs[3]) / 255
    return total / count


def smoothstep(value: float) -> float:
    value = min(1.0, max(0.0, value))
    return 3 * value * value - 2 * value * value * value


def render_video(pattern: Path, output: Path, fps: int) -> None:
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-framerate", str(fps), "-i", str(pattern),
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
            str(output),
        ],
        check=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--first", type=Path, required=True)
    parser.add_argument("--second", type=Path, required=True)
    parser.add_argument("--prop", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--clip-id", required=True)
    parser.add_argument("--motion-source-px", type=int, default=152)
    parser.add_argument("--motion-start-frame", type=int, default=48)
    parser.add_argument("--motion-end-frame", type=int, default=184)
    parser.add_argument("--prop-through-frame", type=int)
    args = parser.parse_args()

    first_root = resolve(args.first, strict=True)
    second_root = resolve(args.second, strict=True)
    prop_path = resolve(args.prop, strict=True)
    output = resolve(args.output, strict=False)
    if output.exists():
        raise RuntimeError(f"refusing to overwrite {output}")
    output.mkdir(parents=True)

    first = frames(first_root)
    second = frames(second_root)
    first_last = Image.open(first[-1]).convert("RGBA")
    second_first = Image.open(second[0]).convert("RGBA")
    if first_last.size != (960, 640) or second_first.size != (960, 640):
        raise ValueError("both stages must use the canonical 960x640 compiled canvas")
    prop = Image.open(prop_path).convert("RGBA").crop((0, 144, 960, 784))
    seam_left = first_last
    if args.prop_through_frame is not None and args.prop_through_frame >= len(first) - 1:
        seam_left = Image.new("RGBA", first_last.size, (0, 0, 0, 0))
        seam_left.alpha_composite(prop)
        seam_left.alpha_composite(first_last)
    seam = premultiplied_difference(seam_left, second_first)
    if seam > 0.015:
        raise ValueError(f"strict stage seam difference {seam:.6f} exceeds 0.015")

    combined_root = output / "frames"
    combined_root.mkdir()
    sources = first + second[1:]
    for index, source in enumerate(sources):
        shutil.copy2(source, combined_root / f"frame-{index:03d}.png")

    review_root = output / "review-frames"
    review_root.mkdir()
    canvas_size = (960 + args.motion_source_px, 640)
    movement_end = min(args.motion_end_frame, len(first) - 1)
    for index, source in enumerate(sources):
        if index <= args.motion_start_frame:
            pet_x = 0
        elif index >= movement_end:
            pet_x = args.motion_source_px
        else:
            progress = (index - args.motion_start_frame) / (movement_end - args.motion_start_frame)
            pet_x = round(args.motion_source_px * smoothstep(progress))
        canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
        if args.prop_through_frame is None or index <= args.prop_through_frame:
            canvas.alpha_composite(prop, (args.motion_source_px, 0))
        canvas.alpha_composite(Image.open(source).convert("RGBA"), (pet_x, 0))
        canvas.save(review_root / f"frame-{index:03d}.png", optimize=True)

    previews = output / "previews"
    previews.mkdir()
    render_video(review_root / "frame-%03d.png", previews / "scene-edge-environment-normal.mp4", 24)
    render_video(review_root / "frame-%03d.png", previews / "scene-edge-environment-2x-slow.mp4", 12)

    selected = list(range(0, len(sources), 8))
    if selected[-1] != len(sources) - 1:
        selected.append(len(sources) - 1)
    columns = 6
    cell = (320, 200)
    rows = math.ceil(len(selected) / columns)
    sheet = Image.new("RGB", (columns * cell[0], rows * cell[1]), (29, 32, 37))
    draw = ImageDraw.Draw(sheet)
    for position, source_index in enumerate(selected):
        image = Image.open(review_root / f"frame-{source_index:03d}.png").convert("RGBA")
        image.thumbnail((cell[0] - 8, cell[1] - 24), Image.Resampling.LANCZOS)
        x = position % columns * cell[0] + (cell[0] - image.width) // 2
        y = position // columns * cell[1] + 20
        sheet.paste(image.convert("RGB"), (x, y))
        draw.text((position % columns * cell[0] + 5, position // columns * cell[1] + 4), f"frame {source_index:03d}", fill="white")
    sheet.save(output / "contact-dark-every8f.jpg", quality=92)

    combined = frames(combined_root)
    manifest = {
        "schema": 1,
        "status": "mechanical-pass-pending-internal-visual-review",
        "humanApproved": False,
        "clipId": args.clip_id,
        "from": "rest.prone.left",
        "to": "gateway.pillow.b",
        "fps": 24,
        "selectedFrames": len(combined),
        "stageBoundary": {
            "firstLastRuntimeFrame": len(first) - 1,
            "secondFirstOmittedAsDuplicate": True,
            "premultipliedDifference": round(seam, 6),
        },
        "processing": {
            "sourceFramesModified": False,
            "concatenationOnly": True,
            "interpolation": False,
            "opticalFlow": False,
            "rife": False,
            "bones": False,
            "crossfade": False,
            "reversePlayback": False,
            "mirroring": False,
            "perFrameRepositioning": False,
        },
        "runtime": {
            "environmentProp": "pillow",
            "environmentPropFixed": True,
            "environmentPropVisibleThroughRuntimeFrame": args.prop_through_frame,
            "petMotionSourcePixels": args.motion_source_px,
            "motionStartRuntimeFrame": args.motion_start_frame,
            "motionEndRuntimeFrame": movement_end,
            "ordinaryAutonomousInterruptible": False,
            "directControlInterruptible": False,
            "targetRuntimeFrame": 0,
            "preloadTargetBeforePlayback": "pillow-gateway-b-loop-v1",
        },
        "sources": [
            {
                "path": first_root.relative_to(ROOT).as_posix(),
                "frames": len(first),
                "orderedSequenceDigest": sequence_digest(first),
            },
            {
                "path": second_root.relative_to(ROOT).as_posix(),
                "frames": len(second),
                "orderedSequenceDigest": sequence_digest(second),
                "firstFrameOmitted": True,
            },
        ],
        "factSource": {
            "path": combined_root.relative_to(ROOT).as_posix(),
            "frames": len(combined),
            "orderedSequenceDigest": sequence_digest(combined),
        },
        "environmentProp": {
            "path": prop_path.relative_to(ROOT).as_posix(),
            "sha256": sha256(prop_path),
            "reviewOffsetSourcePx": [args.motion_source_px, 0],
        },
        "previews": {
            "normal": "previews/scene-edge-environment-normal.mp4",
            "twoTimesSlow": "previews/scene-edge-environment-2x-slow.mp4",
            "contact": "contact-dark-every8f.jpg",
        },
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == "__main__":
    main()
