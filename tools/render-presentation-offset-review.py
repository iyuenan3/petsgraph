#!/usr/bin/env python3
"""Render standard-speed evidence for transient presentation offsets."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from typing import Any

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--source-frames", type=Path, required=True)
    parser.add_argument("--clip-id", required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    return parser.parse_args()


def within_repo(path: Path, *, strict: bool) -> Path:
    result = path if path.is_absolute() else ROOT / path
    result = result.resolve(strict=strict)
    result.relative_to(ROOT)
    return result


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def font(size: int) -> ImageFont.ImageFont:
    for candidate in (
        Path("/System/Library/Fonts/PingFang.ttc"),
        Path("/System/Library/Fonts/Supplemental/Arial Unicode.ttf"),
    ):
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def ffmpeg_writer(path: Path, width: int, height: int, fps: float) -> subprocess.Popen[bytes]:
    return subprocess.Popen(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "rawvideo",
            "-pixel_format",
            "rgb24",
            "-video_size",
            f"{width}x{height}",
            "-framerate",
            str(fps),
            "-i",
            "-",
            "-an",
            "-c:v",
            "libx264",
            "-preset",
            "medium",
            "-crf",
            "16",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            "-y",
            str(path),
        ],
        stdin=subprocess.PIPE,
    )


def finish(writer: subprocess.Popen[bytes]) -> None:
    if writer.stdin is None:
        raise RuntimeError("ffmpeg writer has no stdin")
    writer.stdin.close()
    if writer.wait() != 0:
        raise RuntimeError("ffmpeg review encode failed")


def write_frame(writer: subprocess.Popen[bytes], image: Image.Image) -> None:
    if writer.stdin is None:
        raise RuntimeError("ffmpeg writer has no stdin")
    writer.stdin.write(image.convert("RGB").tobytes())


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    args = parse_args()
    package = within_repo(args.package, strict=True)
    source_frames = within_repo(args.source_frames, strict=True)
    output = within_repo(args.output_directory, strict=False)
    output.mkdir(parents=True, exist_ok=False)

    clip = read_json(package / "clips" / f"{args.clip_id}.json")
    frames = clip["frames"]
    media = clip.get("media", {})
    fps = float(media.get("frameRate", 1_000 / float(frames[0]["durationMs"])))
    source_paths = [source_frames / f"{index:04d}.png" for index in range(len(frames))]
    if not all(path.is_file() for path in source_paths):
        raise ValueError("the source frame sequence is incomplete")

    compare_path = output / "floor-prone-to-cat-bed-original-left-corrected-right-standard.mp4"
    split_path = output / "floor-prone-to-cat-bed-corrected-dark-left-light-right-standard.mp4"
    compare_writer = ffmpeg_writer(compare_path, 1800, 320, fps)
    split_writer = ffmpeg_writer(split_path, 900, 320, fps)
    label_font = font(26)
    offsets: list[float] = []

    for index, (definition, source_path) in enumerate(zip(frames, source_paths, strict=True)):
        offset = float((definition.get("presentationOffsetPx") or [0])[0])
        offsets.append(offset)
        with Image.open(source_path) as opened:
            rgba = opened.convert("RGBA")

        comparison = Image.new("RGBA", (1800, 320), (31, 33, 36, 255))
        draw = ImageDraw.Draw(comparison)
        draw.rectangle((900, 0, 1799, 319), fill=(31, 33, 36, 255))
        draw.line((900, 0, 900, 320), fill=(95, 99, 104, 255), width=2)
        draw.text((28, 15), "原稿", fill=(245, 245, 245, 255), font=label_font)
        draw.text((928, 15), "位移修正", fill=(245, 245, 245, 255), font=label_font)
        comparison.alpha_composite(rgba, (60, 64))
        comparison.alpha_composite(rgba, (960 + round(offset), 64))
        write_frame(compare_writer, comparison)

        split = Image.new("RGBA", (900, 320), (31, 33, 36, 255))
        split_draw = ImageDraw.Draw(split)
        split_draw.rectangle((450, 0, 899, 319), fill=(244, 244, 244, 255))
        split.alpha_composite(rgba, (60 + round(offset), 64))
        write_frame(split_writer, split)

    finish(compare_writer)
    finish(split_writer)

    source_media = package / str(media["src"])
    manifest = {
        "schema": 1,
        "status": "assistant-review-built-awaiting-Maxwell-visual-review",
        "clipId": args.clip_id,
        "frameCount": len(frames),
        "frameRate": fps,
        "sourceFrames": str(source_frames.relative_to(ROOT)),
        "package": str(package.relative_to(ROOT)),
        "sourceMediaSha256": sha256(source_media),
        "presentationOffset": {
            "axis": "x",
            "unit": "source-pixel",
            "firstPx": offsets[0],
            "lastPx": offsets[-1],
            "maximumPx": max(offsets),
            "maximumFrameDeltaPx": max(
                abs(offsets[index + 1] - offsets[index])
                for index in range(len(offsets) - 1)
            ),
            "scaleChanged": False,
            "sourcePixelsChanged": False,
            "frameOrderChanged": False,
            "frameTimingChanged": False,
        },
        "reviews": [
            {
                "path": str(compare_path.relative_to(ROOT)),
                "sha256": sha256(compare_path),
                "layout": "original-left-corrected-right",
            },
            {
                "path": str(split_path.relative_to(ROOT)),
                "sha256": sha256(split_path),
                "layout": "corrected-dark-left-light-right",
            },
        ],
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
