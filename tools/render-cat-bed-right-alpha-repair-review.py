#!/usr/bin/env python3
"""Render one standard-speed review tour for Feiliu's cat-bed alpha repair."""

from __future__ import annotations

import argparse
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
FFMPEG = "/opt/homebrew/bin/ffmpeg"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def within_repo(path: Path, *, strict: bool) -> Path:
    result = path if path.is_absolute() else ROOT / path
    result = result.resolve(strict=strict)
    result.relative_to(ROOT)
    return result


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def font(size: int):
    for candidate in (
        Path("/System/Library/Fonts/PingFang.ttc"),
        Path("/System/Library/Fonts/STHeiti Medium.ttc"),
    ):
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


TITLE_FONT = font(23)
PANEL_FONT = font(18)


def composite(rgba: Image.Image, background: Image.Image) -> Image.Image:
    canvas = background.convert("RGBA")
    canvas.alpha_composite(rgba.convert("RGBA"))
    return canvas.convert("RGB")


def solid(size: tuple[int, int], color: tuple[int, int, int]) -> Image.Image:
    return Image.new("RGB", size, color)


def checker(size: tuple[int, int], cell: int = 12) -> Image.Image:
    width, height = size
    y, x = np.indices((height, width))
    field = ((x // cell + y // cell) % 2).astype(np.uint8)
    rgb = np.where(field[..., None] == 0, 196, 232).astype(np.uint8)
    return Image.fromarray(np.repeat(rgb, 3, axis=2), "RGB")


def review_frame(before: Image.Image, after: Image.Image, title: str) -> Image.Image:
    width, height = before.size
    banner = 50
    output = Image.new("RGB", (width * 2, banner + height * 2), (18, 19, 22))
    panels = (
        (composite(before, solid(before.size, (245, 245, 245))), (0, banner), "修复前，白底"),
        (composite(after, solid(after.size, (245, 245, 245))), (width, banner), "修复后，白底"),
        (composite(after, solid(after.size, (28, 28, 31))), (0, banner + height), "修复后，深色"),
        (composite(after, checker(after.size)), (width, banner + height), "修复后，棋盘"),
    )
    for panel, position, _ in panels:
        output.paste(panel, position)
    draw = ImageDraw.Draw(output)
    draw.text((12, 10), title, font=TITLE_FONT, fill=(250, 250, 250))
    for _, (x, y), label in panels:
        draw.rectangle((x, y, x + 180, y + 28), fill=(0, 0, 0))
        draw.text((x + 8, y + 4), label, font=PANEL_FONT, fill=(255, 255, 255))
    return output


def cat_bed_clip_ids(graph: dict[str, Any]) -> list[str]:
    scene = {str(node["id"]): str(node.get("scene", "")) for node in graph.get("nodes", [])}
    ids = {
        str(node["loopClip"])
        for node in graph.get("nodes", [])
        if scene.get(str(node["id"])) == "cat-bed"
    }
    ids.update(
        str(edge["clip"])
        for edge in graph.get("edges", [])
        if scene.get(str(edge["from"])) == "cat-bed"
        or scene.get(str(edge["to"])) == "cat-bed"
    )
    return sorted(ids)


def main() -> None:
    args = parse_args()
    before = within_repo(args.before, strict=True)
    after = within_repo(args.after, strict=True)
    output = within_repo(args.output, strict=False)
    if output.exists():
        raise FileExistsError(f"refusing to overwrite {output}")
    output.mkdir(parents=True)

    before_graph = read_json(before / "graph.json")
    after_graph = read_json(after / "graph.json")
    if before_graph != after_graph:
        raise ValueError("graph changed during cat-bed alpha repair")
    if (before / "behavior.json").read_bytes() != (after / "behavior.json").read_bytes():
        raise ValueError("behavior changed during cat-bed alpha repair")
    clip_ids = cat_bed_clip_ids(after_graph)
    if len(clip_ids) != 15:
        raise ValueError(f"expected 15 cat-bed clips, found {len(clip_ids)}")

    segment_dir = output / "segments"
    segment_dir.mkdir()
    concat_lines = []
    clip_reports = []
    with tempfile.TemporaryDirectory(prefix="petsgraph-cat-bed-right-review-") as scratch_text:
        scratch = Path(scratch_text)
        for clip_id in clip_ids:
            before_clip = read_json(before / "clips" / f"{clip_id}.json")
            after_clip = read_json(after / "clips" / f"{clip_id}.json")
            before_provenance = before_clip.pop("provenance", None)
            after_provenance = after_clip.pop("provenance", None)
            if before_clip != after_clip:
                raise ValueError(f"frame contract changed: {clip_id}")
            if not before_provenance or not after_provenance:
                raise ValueError(f"missing provenance: {clip_id}")
            before_paths = sorted((before / "frames" / clip_id).glob("*.png"))
            after_paths = sorted((after / "frames" / clip_id).glob("*.png"))
            if len(before_paths) != len(after_paths) or not before_paths:
                raise ValueError(f"frame count mismatch: {clip_id}")
            frame_dir = scratch / clip_id
            frame_dir.mkdir()
            alpha_decrease_pixels = 0
            changed_without_alpha_increase = 0
            changed_frames = 0
            alpha_increase_pixels = 0
            for index, (before_path, after_path) in enumerate(
                zip(before_paths, after_paths, strict=True)
            ):
                before_image = Image.open(before_path).convert("RGBA")
                after_image = Image.open(after_path).convert("RGBA")
                before_rgba = np.asarray(before_image)
                after_rgba = np.asarray(after_image)
                if before_rgba.shape != after_rgba.shape:
                    raise ValueError(f"frame size changed: {clip_id} frame {index + 1}")
                increase = after_rgba[..., 3] > before_rgba[..., 3]
                decrease = after_rgba[..., 3] < before_rgba[..., 3]
                changed = np.any(after_rgba != before_rgba, axis=2)
                alpha_decrease_pixels += int(decrease.sum())
                changed_without_alpha_increase += int((changed & ~increase).sum())
                alpha_increase_pixels += int(increase.sum())
                changed_frames += int(changed.any())
                rendered = review_frame(
                    before_image,
                    after_image,
                    f"{clip_id}  frame {index + 1}/{len(before_paths)}",
                )
                rendered.save(frame_dir / f"{index + 1:06d}.png", compress_level=2)
            if alpha_decrease_pixels or changed_without_alpha_increase:
                raise RuntimeError(
                    f"repair changed locked pixels: {clip_id}; "
                    f"alphaDecrease={alpha_decrease_pixels}, "
                    f"changedWithoutIncrease={changed_without_alpha_increase}"
                )
            duration_ms = float(before_clip["frames"][0]["durationMs"])
            authored_fps = Fraction(1_000_000, round(duration_ms * 1000)).limit_denominator(1000)
            segment = segment_dir / f"{clip_id}.mp4"
            subprocess.run(
                [
                    FFMPEG,
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-framerate",
                    f"{authored_fps.numerator}/{authored_fps.denominator}",
                    "-i",
                    str(frame_dir / "%06d.png"),
                    "-vf",
                    "fps=24",
                    "-c:v",
                    "libx264",
                    "-preset",
                    "slow",
                    "-crf",
                    "14",
                    "-pix_fmt",
                    "yuv420p",
                    "-movflags",
                    "+faststart",
                    str(segment),
                ],
                check=True,
            )
            shutil.rmtree(frame_dir)
            concat_lines.append(f"file '{segment.as_posix()}'")
            clip_reports.append(
                {
                    "clipId": clip_id,
                    "frameCount": len(before_paths),
                    "authoredFps": f"{authored_fps.numerator}/{authored_fps.denominator}",
                    "changedFrameCount": changed_frames,
                    "alphaIncreasePixelsCompiled": alpha_increase_pixels,
                    "alphaDecreasePixelsCompiled": alpha_decrease_pixels,
                    "changedPixelsWithoutAlphaIncrease": changed_without_alpha_increase,
                    "beforeSequenceDigest": hashlib.sha256(
                        b"".join(bytes.fromhex(sha256(path)) for path in before_paths)
                    ).hexdigest(),
                    "afterSequenceDigest": hashlib.sha256(
                        b"".join(bytes.fromhex(sha256(path)) for path in after_paths)
                    ).hexdigest(),
                    "reviewSegment": segment.relative_to(output).as_posix(),
                }
            )

    concat_path = output / "concat.txt"
    concat_path.write_text("\n".join(concat_lines) + "\n", encoding="utf-8")
    tour = output / "feiliu-cat-bed-right-alpha-before-after-standard.mp4"
    subprocess.run(
        [
            FFMPEG,
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat_path),
            "-c",
            "copy",
            str(tour),
        ],
        check=True,
    )
    write_json(
        output / "manifest.json",
        {
            "schema": 1,
            "status": "assistant-mechanical-qa-pass-awaiting-visual-review",
            "scope": "cat-bed right-side alpha repair only",
            "before": before.relative_to(ROOT).as_posix(),
            "after": after.relative_to(ROOT).as_posix(),
            "graphByteIdentical": True,
            "behaviorByteIdentical": True,
            "clipFrameContractsIdenticalExceptProvenance": True,
            "alphaDecreasePixelsCompiled": sum(item["alphaDecreasePixelsCompiled"] for item in clip_reports),
            "changedPixelsWithoutAlphaIncrease": sum(item["changedPixelsWithoutAlphaIncrease"] for item in clip_reports),
            "clipCount": len(clip_reports),
            "clips": clip_reports,
            "tour": tour.relative_to(output).as_posix(),
        },
    )
    print(json.dumps({"output": output.as_posix(), "tour": tour.as_posix()}, ensure_ascii=False))


if __name__ == "__main__":
    main()
