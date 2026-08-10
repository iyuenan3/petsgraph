#!/usr/bin/env python3
"""Render a compiled quiet-companion scene round trip with its fixed prop."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CLIPS = [
    "prone-left-long-loop-v1",
    "prone-left-to-pillow-gateway-b-v18",
    "pillow-gateway-b-loop-v1",
    "pillow-gateway-b-to-head-on-pillow-v1",
    "head-on-pillow-loop-v1",
    "head-on-pillow-to-pillow-gateway-b-v1",
    "pillow-gateway-b-loop-v1",
    "pillow-gateway-b-to-prone-left-v5",
    "prone-left-long-loop-v1",
]


def resolve(path: Path, *, strict: bool) -> Path:
    value = path if path.is_absolute() else ROOT / path
    value = value.resolve(strict=strict)
    value.relative_to(ROOT)
    return value


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def composite_review(image: Image.Image) -> Image.Image:
    dark = Image.new("RGBA", image.size, (29, 32, 37, 255))
    light = Image.new("RGBA", image.size, (238, 240, 243, 255))
    dark.alpha_composite(image)
    light.alpha_composite(image)
    result = Image.new("RGB", (image.width * 2, image.height))
    result.paste(dark.convert("RGB"), (0, 0))
    result.paste(light.convert("RGB"), (image.width, 0))
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--clip", action="append", dest="clips")
    args = parser.parse_args()

    package = resolve(args.package, strict=True)
    output = resolve(args.output, strict=False)
    if output.exists():
        raise FileExistsError(f"refusing to overwrite {output}")
    output.mkdir(parents=True)
    previews = output / "previews"
    critical = output / "critical-frames"
    previews.mkdir()
    critical.mkdir()

    manifest = load_json(package / "package.json")
    art = manifest["art"]
    canvas_width, canvas_height = art["canvasPx"]
    base_height = float(art["baseHeightPt"])
    props = manifest["renderAssets"].get("environmentProps", [])
    if len(props) != 1:
        raise ValueError("round-trip review currently requires exactly one environment prop")
    prop_definition = props[0]
    visibility = prop_definition["visibility"]
    if visibility not in ("persistent", "node-scenes", "embedded"):
        raise ValueError(f"unsupported environment prop visibility: {visibility}")
    visible_loop_clips: set[str] = set()
    if visibility == "node-scenes":
        scenes = set(prop_definition.get("scenes", []))
        graph = load_json(package / manifest["graph"])
        visible_loop_clips = {
            node["loopClip"]
            for node in graph["nodes"]
            if node.get("scene") in scenes
        }
    prop_path = package / prop_definition["src"]
    prop = Image.open(prop_path).convert("RGBA")
    if prop.size != (canvas_width, canvas_height):
        raise ValueError("environment prop size must match the compiled canvas")
    pixels_per_point = canvas_height / base_height
    prop_x = round(prop_definition["offsetFromFloorOriginPt"][0] * pixels_per_point)
    prop_y = round(prop_definition["offsetFromFloorOriginPt"][1] * pixels_per_point)

    clip_ids = args.clips or DEFAULT_CLIPS
    clips: list[dict] = []
    for clip_id in clip_ids:
        path = package / "clips" / f"{clip_id}.json"
        clip = load_json(path)
        if clip["id"] != clip_id:
            raise ValueError(f"clip id mismatch in {path}")
        clips.append(clip)

    accumulated_pt = 0.0
    frame_records: list[dict] = []
    segment_records: list[dict] = []
    positions_px = [0, prop_x]
    for segment_index, clip in enumerate(clips):
        sign = -1.0 if clip["rootMotionEndPt"][0] > 0 and clip["facing"] == "left" else 1.0
        segment_start_pt = accumulated_pt
        for frame_index, frame in enumerate(clip["frames"]):
            position_pt = segment_start_pt + sign * float(frame["rootMotionPt"][0])
            position_px = round(position_pt * pixels_per_point)
            positions_px.append(position_px)
            frame_records.append(
                {
                    "segmentIndex": segment_index,
                    "clipID": clip["id"],
                    "frameIndex": frame_index,
                    "src": package / frame["src"],
                    "positionPt": position_pt,
                    "positionPx": position_px,
                    "showProp": (
                        visibility == "persistent"
                        or clip["id"] in visible_loop_clips
                    ),
                }
            )
        accumulated_pt += sign * float(clip["rootMotionEndPt"][0])
        segment_records.append(
            {
                "index": segment_index,
                "clipID": clip["id"],
                "frames": len(clip["frames"]),
                "facing": clip["facing"],
                "rootMotionEndPt": clip["rootMotionEndPt"],
                "windowStartPt": segment_start_pt,
                "windowEndPt": accumulated_pt,
            }
        )

    if abs(accumulated_pt) > 0.000_001:
        raise ValueError(f"round trip does not return to its origin: {accumulated_pt}")
    origin_x = -min(positions_px + [0])
    review_width = canvas_width + max(positions_px + [prop_x]) + origin_x
    review_height = max(canvas_height, canvas_height + prop_y)
    frame_size = (review_width * 2, review_height)

    selected_indices = {0, len(frame_records) - 1}
    cursor = 0
    for segment in segment_records:
        selected_indices.add(cursor)
        selected_indices.add(cursor + segment["frames"] - 1)
        cursor += segment["frames"]
    selected_indices.update(range(0, len(frame_records), 48))

    def render(index: int, record: dict) -> Image.Image:
        scene = Image.new("RGBA", (review_width, review_height), (0, 0, 0, 0))
        if record["showProp"]:
            scene.alpha_composite(prop, (origin_x + prop_x, prop_y))
        pet = Image.open(record["src"]).convert("RGBA")
        if pet.size != (canvas_width, canvas_height):
            raise ValueError(f"compiled frame has unexpected size: {record['src']}")
        scene.alpha_composite(pet, (origin_x + record["positionPx"], 0))
        review = composite_review(scene)
        if index in selected_indices:
            review.save(
                critical / f"frame-{index:04d}-{record['clipID']}-{record['frameIndex']:04d}.png",
                optimize=True,
            )
        return review

    for fps, name in ((24, "normal"), (12, "2x-slow")):
        target = previews / f"quiet-scene-round-trip-{name}.mp4"
        process = subprocess.Popen(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-f", "rawvideo", "-pixel_format", "rgb24",
                "-video_size", f"{frame_size[0]}x{frame_size[1]}",
                "-framerate", str(fps), "-i", "-",
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
                str(target),
            ],
            stdin=subprocess.PIPE,
        )
        assert process.stdin is not None
        try:
            for index, record in enumerate(frame_records):
                process.stdin.write(render(index, record).tobytes())
        finally:
            process.stdin.close()
        if process.wait() != 0:
            raise RuntimeError(f"ffmpeg failed for {target}")

    thumbs: list[tuple[int, Image.Image]] = []
    for index in sorted(selected_indices):
        record = frame_records[index]
        source = next(critical.glob(f"frame-{index:04d}-*.png"))
        image = Image.open(source).convert("RGB")
        image.thumbnail((360, 220), Image.Resampling.LANCZOS)
        thumbs.append((index, image.copy()))
    columns = 4
    cell_width, cell_height = 370, 250
    sheet = Image.new(
        "RGB",
        (columns * cell_width, math.ceil(len(thumbs) / columns) * cell_height),
        (29, 32, 37),
    )
    draw = ImageDraw.Draw(sheet)
    for position, (index, image) in enumerate(thumbs):
        column = position % columns
        row = position // columns
        x = column * cell_width + (cell_width - image.width) // 2
        y = row * cell_height + 26
        sheet.paste(image, (x, y))
        record = frame_records[index]
        draw.text(
            (column * cell_width + 5, row * cell_height + 5),
            f"{index:04d} {record['clipID']}:{record['frameIndex']:04d}",
            fill="white",
        )
    sheet.save(output / "contact-sheet.jpg", quality=92)

    result = {
        "schema": 1,
        "status": "internal-runtime-contract-review-pending-Maxwell",
        "package": package.relative_to(ROOT).as_posix(),
        "packageManifestSha256": digest(package / "package.json"),
        "sourceFramesModified": False,
        "interpolationUsed": False,
        "environmentProp": {
            "id": prop_definition["id"],
            "src": prop_definition["src"],
            "sha256": digest(prop_path),
            "fixedPositionPx": [prop_x, prop_y],
            "visibility": visibility,
            "visibleLoopClips": sorted(visible_loop_clips),
        },
        "canvasPx": [canvas_width, canvas_height],
        "reviewFramePx": list(frame_size),
        "frames": len(frame_records),
        "durationSeconds": len(frame_records) / 24,
        "terminalWindowOffsetPt": accumulated_pt,
        "segments": segment_records,
        "normalPreview": "previews/quiet-scene-round-trip-normal.mp4",
        "twoTimesSlowPreview": "previews/quiet-scene-round-trip-2x-slow.mp4",
    }
    (output / "manifest.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
