#!/usr/bin/env python3
"""Build Feiliu's approved fine-matte graph as an immutable frame package."""

from __future__ import annotations

import argparse
from datetime import datetime
from fractions import Fraction
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import tempfile
from typing import Any
from zoneinfo import ZoneInfo

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_VERSION = "0.4.0"
MASTER_CANVAS = (1440, 900)
MASTER_CROP = (64, 338, 1376, 786)
OUTPUT_SCALE = Fraction(1, 2)
OUTPUT_CANVAS = (
    round((MASTER_CROP[2] - MASTER_CROP[0]) * float(OUTPUT_SCALE)),
    round((MASTER_CROP[3] - MASTER_CROP[1]) * float(OUTPUT_SCALE)),
)
MASTER_GROUND_Y = 704.0
OUTPUT_GROUND_Y = (MASTER_GROUND_Y - MASTER_CROP[1]) * float(OUTPUT_SCALE)
FINAL_MANIFEST = Path(
    "workspaces/feiliu-private/goal-2026-08-16/"
    "feiliu-selective-fine-matte-graph-tour-v2/manifest.json"
)

NODE_METADATA: dict[str, dict[str, Any]] = {
    "sit.front.floor": dict(name="正面坐姿", posture="sit", scene="floor", role="interaction", autonomous=False),
    "rest.floor.prone.right": dict(name="平趴睡", posture="prone", scene="floor", role="dwell", autonomous=True),
    "rest.floor.side-stretched.right": dict(name="侧身伸展睡", posture="side-stretched", scene="floor", role="dwell", autonomous=True),
    "rest.floor.tight-curled.right": dict(name="紧蜷睡", posture="tight-curled", scene="floor", role="dwell", autonomous=True),
    "rest.floor.semi-supine.right": dict(name="半仰睡", posture="semi-supine", scene="floor", role="dwell", autonomous=True),
    "rest.floor.full-supine.right": dict(name="仰躺睡", posture="full-supine", scene="floor", role="dwell", autonomous=True),
    "sit.front.cat-bed": dict(name="猫窝正面坐姿", posture="sit", scene="cat-bed", role="interaction", autonomous=False),
    "rest.cat-bed.curled": dict(name="猫窝蜷睡", posture="curled", scene="cat-bed", role="dwell", autonomous=True),
    "rest.cat-bed.prone": dict(name="猫窝自然趴睡", posture="prone", scene="cat-bed", role="dwell", autonomous=True),
    "rest.cat-bed.side-stretched": dict(name="猫窝侧伸睡", posture="side-stretched", scene="cat-bed", role="dwell", autonomous=True),
    "rest.cat-bed.stretch-open-belly": dict(name="猫窝舒展露腹睡", posture="open-belly", scene="cat-bed", role="dwell", autonomous=True),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", default="0.5.0-preview.1")
    return parser.parse_args()


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


def sequence_digest(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in paths:
        digest.update(path.name.encode("utf-8"))
        digest.update(b"\0")
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        digest.update(b"\n")
    return digest.hexdigest()


def premultiplied_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8)
    alpha = rgba[..., 3].astype(np.float32)
    premul = np.rint(rgba[..., :3].astype(np.float32) * (alpha[..., None] / 255.0)).astype(np.uint8)
    premul_scaled = np.asarray(
        Image.fromarray(premul, "RGB").resize(size, Image.Resampling.LANCZOS),
        dtype=np.float32,
    )
    alpha_scaled = np.asarray(
        Image.fromarray(alpha.astype(np.uint8), "L").resize(size, Image.Resampling.LANCZOS),
        dtype=np.uint8,
    )
    unit = alpha_scaled.astype(np.float32)[..., None] / 255.0
    rgb = np.zeros_like(premul_scaled)
    np.divide(premul_scaled, np.maximum(unit, 1.0 / 255.0), out=rgb, where=unit > 0)
    output = np.empty((size[1], size[0], 4), dtype=np.uint8)
    output[..., :3] = np.rint(np.clip(rgb, 0, 255)).astype(np.uint8)
    output[..., 3] = alpha_scaled
    return Image.fromarray(output, "RGBA")


def compile_frame(source: Path, transform: dict[str, Any]) -> Image.Image:
    with Image.open(source) as image:
        scale = float(transform["uniformScale"])
        scaled = premultiplied_resize(
            image,
            (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        )
    tx, ty = [round(float(value)) for value in transform["translatePx"]]
    master = Image.new("RGBA", MASTER_CANVAS, (0, 0, 0, 0))
    master.alpha_composite(scaled, (tx, ty))
    cropped = master.crop(MASTER_CROP)
    return premultiplied_resize(cropped, OUTPUT_CANVAS)


def alpha_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    bounds = image.getchannel("A").point(lambda value: 255 if value >= 8 else 0).getbbox()
    if bounds is None:
        raise ValueError("compiled frame contains no visible subject")
    return bounds


def frame_contract(bounds: tuple[int, int, int, int], *, scene: str) -> dict[str, Any]:
    left, top, right, bottom = bounds
    width, height = right - left, bottom - top
    content = [float(left), float(top), float(width), float(height)]
    if scene == "cat-bed":
        hit = [left + width * 0.12, top + height * 0.04, width * 0.76, height * 0.78]
        props: dict[str, list[float]] | None = {"cat-bed": content}
    else:
        hit = [left + width * 0.03, top + height * 0.02, width * 0.94, height * 0.96]
        props = None
    return {
        "contentBoundsPx": content,
        "petBoundsPx": content,
        "propBoundsPx": props,
        "anchorsPx": {
            "root": [left + width / 2, OUTPUT_GROUND_Y],
            "ground": [left + width / 2, OUTPUT_GROUND_Y],
            "head": [left + width * 0.6, top + height * 0.25],
        },
        "collision": {
            "bodyCoreEllipsePx": [left + width * 0.08, top + height * 0.08, width * 0.84, height * 0.84],
            "screenBoundsPx": content,
            "petHitEllipsePx": hit,
        },
        "rootMotionPt": [0.0, 0.0],
    }


def integrity_manifest(root: Path) -> dict[str, Any]:
    entries = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.name == "integrity.json":
            continue
        entries.append({
            "path": path.relative_to(root).as_posix(),
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
        })
    return {"schemaVersion": SCHEMA_VERSION, "algorithm": "sha256", "files": entries}


def main() -> None:
    args = parse_args()
    output = args.output if args.output.is_absolute() else ROOT / args.output
    output = output.resolve(strict=False)
    output.relative_to(ROOT)
    if output.suffix != ".petsgraph-pet":
        raise ValueError("--output must end in .petsgraph-pet")
    if output.exists():
        raise FileExistsError(f"refusing to overwrite {output}")
    output.parent.mkdir(parents=True, exist_ok=True)

    final_path = ROOT / FINAL_MANIFEST
    final = read_json(final_path)
    if final.get("status") != "human-approved-selective-fine-matte-graph-tour":
        raise ValueError("Feiliu final graph is not human approved")
    records = final.get("uniqueRecords", [])
    if len(records) != 31 or len({item["clipId"] for item in records}) != 31:
        raise ValueError("Feiliu final graph must contain exactly 31 unique clips")

    loop_records = [item for item in records if item["kind"] in ("node-loop", "node-hold")]
    transition_records = [item for item in records if item["kind"] == "transition"]
    if len(loop_records) != 11 or len(transition_records) != 20:
        raise ValueError("Feiliu graph must contain 11 nodes and 20 directed edges")

    temporary = Path(tempfile.mkdtemp(prefix=f"{output.name}.build-", dir=output.parent))
    clip_summaries = []
    try:
        record_by_node = {item["from"]: item for item in loop_records}
        if set(record_by_node) != set(NODE_METADATA):
            raise ValueError("Feiliu node metadata does not match the approved graph")

        outgoing = {}
        for item in transition_records:
            outgoing.setdefault(item["from"], []).append(item["clipId"])

        for record in records:
            clip_id = str(record["clipId"])
            manifest_path = ROOT / str(record["manifest"])
            if sha256(manifest_path) != str(record["manifestSha256"]):
                raise ValueError(f"approved manifest hash drift: {clip_id}")
            source_manifest = read_json(manifest_path)
            if source_manifest.get("fixedTransform") != record.get("fixedTransform"):
                raise ValueError(f"fixed transform drift: {clip_id}")
            if source_manifest.get("perFrameTransform") is not False:
                raise ValueError(f"per-frame transform is forbidden: {clip_id}")
            fps = Fraction(str(source_manifest["approvedPlaybackFps"]))
            if fps <= 0 or fps > 24:
                raise ValueError(f"invalid approved playback rate: {clip_id}")
            rgba_dir = manifest_path.parent / "clips" / clip_id / "rgba"
            sources = sorted(rgba_dir.glob("*.png"))
            if not sources:
                raise ValueError(f"missing approved RGBA sequence: {clip_id}")
            if record["kind"] == "node-hold" and len(sources) != 1:
                raise ValueError("floor sitting hold must retain its one approved endpoint")

            source_digest = sequence_digest(sources)
            clip_frames = []
            output_dir = temporary / "frames" / clip_id
            output_dir.mkdir(parents=True)
            scene = NODE_METADATA[record["from"]]["scene"]
            for index, source in enumerate(sources):
                compiled = compile_frame(source, record["fixedTransform"])
                bounds = alpha_bounds(compiled)
                destination = output_dir / f"{index:04d}.png"
                compiled.save(destination, format="PNG", optimize=True)
                contract = frame_contract(bounds, scene=scene)
                contract["src"] = destination.relative_to(temporary).as_posix()
                contract["durationMs"] = 1_000.0 / float(fps)
                clip_frames.append(contract)

            is_loop = record["kind"] in ("node-loop", "node-hold")
            preload = sorted(outgoing.get(record["from"], [])) if is_loop else [record_by_node[record["to"]]["clipId"]]
            clip = {
                "schemaVersion": SCHEMA_VERSION,
                "id": clip_id,
                "type": "loop" if is_loop else "transition",
                "facing": "front" if ".front." in record["from"] or record["from"].startswith("sit.front") else "right",
                "mirrorSafe": False,
                "entryPose": record["from"],
                "exitPose": record["to"],
                "safeExitFrames": [len(clip_frames) - 1] if is_loop else [],
                "preloadHints": preload,
                "rootMotionEndPt": [0.0, 0.0],
                "frames": clip_frames,
                "provenance": {
                    "approvalStatus": "human-approved-fine-matte-source",
                    "approvedRecipe": str(record["manifest"]),
                    "approvedRecipeSha256": str(record["manifestSha256"]),
                    "candidateRecipe": FINAL_MANIFEST.as_posix(),
                    "candidateRecipeSha256": sha256(final_path),
                    "sourceSequenceDigest": source_digest,
                    "rootMotionStatus": "zero-in-canvas-motion-only",
                    "normalization": "one-fixed-transform-plus-one-global-crop-and-scale",
                },
            }
            write_json(temporary / "clips" / f"{clip_id}.json", clip)
            clip_summaries.append({
                "clipId": clip_id,
                "kind": record["kind"],
                "from": record["from"],
                "to": record["to"],
                "sourceFrames": len(sources),
                "approvedPlaybackFps": str(fps),
                "sourceSequenceDigest": source_digest,
                "fixedTransform": record["fixedTransform"],
            })

        nodes = []
        for node_id, metadata in NODE_METADATA.items():
            loop = record_by_node[node_id]
            nodes.append({
                "id": node_id,
                "displayName": metadata["name"],
                "posture": metadata["posture"],
                "orientation": "front" if node_id.startswith("sit.front") else "right",
                "grounded": True,
                "stability": "stable",
                "scene": metadata["scene"],
                "role": metadata["role"],
                "autonomousEligible": metadata["autonomous"],
                "props": [],
                "loopClip": loop["clipId"],
            })
        edges = []
        for item in transition_records:
            source_scene = NODE_METADATA[item["from"]]["scene"]
            target_scene = NODE_METADATA[item["to"]]["scene"]
            edge = {
                "id": item["clipId"],
                "from": item["from"],
                "to": item["to"],
                "clip": item["clipId"],
                "kind": "scene-transition" if source_scene != target_scene else "transition",
                "interruptPolicy": "finish-before-retarget",
                "targetStartFrame": 0,
            }
            if source_scene != target_scene:
                edge["sceneChange"] = f"{source_scene}-to-{target_scene}"
            edges.append(edge)
        write_json(temporary / "graph.json", {"schemaVersion": SCHEMA_VERSION, "nodes": nodes, "edges": edges})

        behavior = {
            "schemaVersion": SCHEMA_VERSION,
            "profile": "quiet-sleep-companion",
            "defaultIntent": "sleep",
            "timing": {
                "strategy": "random-long-tail",
                "parametersStatus": "awaiting-human-runtime-review",
                "avoidImmediateRepeat": True,
                "minimumDwellSeconds": 180,
                "medianDwellSeconds": 480,
                "maximumDwellSeconds": 1800,
                "recentHistoryLimit": 2,
                "sameSceneProbability": 0.9,
            },
            "scenePolicy": {
                "floor": {"sticky": True, "gateway": None, "minimumDwellSeconds": 900, "exitCooldownSeconds": 1800},
                "cat-bed": {"sticky": True, "gateway": None, "minimumDwellSeconds": 1800, "exitCooldownSeconds": 1800},
            },
            "interactions": {
                "petClick": {"sleeping": "wake-to-scene-sit", "sitting": "return-to-scene-sleep", "debounceSeconds": 0.35},
                "desktopClick": "ignore",
                "drag": "direct-manipulation",
            },
        }
        write_json(temporary / "behavior.json", behavior)
        write_json(temporary / "demo-sequence.json", {
            "schemaVersion": SCHEMA_VERSION,
            "id": "feiliu-default-sleep",
            "segments": [{"clip": "no-prop-prone-loop-v1", "startFrame": 0, "cycles": 1, "repeatForever": True}],
        })
        review = {
            "schemaVersion": SCHEMA_VERSION,
            "runtimeChainStatus": "fine-matte-source-package-awaiting-desktop-review",
            "installable": False,
            "approvedRuntimeChains": [],
            "remainingRuntimeGates": [
                "compiled package integrity and media validation",
                "dual-pet desktop scale, placement, CPU and memory review",
                "Maxwell runtime visual acceptance",
            ],
            "humanApprovedSourceGraph": FINAL_MANIFEST.as_posix(),
            "humanApprovedSourceGraphSha256": sha256(final_path),
            "clips": clip_summaries,
        }
        write_json(temporary / "reviews" / "index.json", review)
        write_json(temporary / "source-assets.json", {
            "schemaVersion": SCHEMA_VERSION,
            "sourceGraph": FINAL_MANIFEST.as_posix(),
            "sourceGraphSha256": sha256(final_path),
            "masterCanvasPx": list(MASTER_CANVAS),
            "masterCropPx": [MASTER_CROP[0], MASTER_CROP[1], MASTER_CROP[2] - MASTER_CROP[0], MASTER_CROP[3] - MASTER_CROP[1]],
            "outputScale": f"{OUTPUT_SCALE.numerator}/{OUTPUT_SCALE.denominator}",
            "outputCanvasPx": list(OUTPUT_CANVAS),
            "masterGroundYPx": MASTER_GROUND_Y,
            "outputGroundYPx": OUTPUT_GROUND_Y,
            "perFrameGeometry": False,
            "temporalInterpolation": False,
            "clips": clip_summaries,
        })
        write_json(temporary / "package.json", {
            "schemaVersion": SCHEMA_VERSION,
            "package": {"id": "feiliu-quiet-companion", "version": args.version, "createdAt": datetime.now(ZoneInfo("Asia/Shanghai")).strftime("%Y-%m-%dT%H:%M:%S%z")},
            "pet": {"id": "feiliu", "displayName": "飞流", "species": "cat", "identityStyle": "faithful-real-pet"},
            "art": {"canvasPx": list(OUTPUT_CANVAS), "baseHeightPt": 150.0, "coordinateOrigin": "top-left", "defaultNode": "rest.floor.prone.right", "groundYPx": OUTPUT_GROUND_Y},
            "renderAssets": {"mode": "frames", "pixelFormat": "rgba8-straight", "environmentProps": []},
            "scenes": [
                {"id": "floor", "displayName": "地面", "order": 0},
                {"id": "cat-bed", "displayName": "猫窝", "order": 1},
            ],
            "graph": "graph.json",
            "behavior": "behavior.json",
            "reviewIndex": "reviews/index.json",
            "integrity": "integrity.json",
            "sourceAssets": "source-assets.json",
        })
        write_json(temporary / "integrity.json", integrity_manifest(temporary))
        os.replace(temporary, output)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise

    print(json.dumps({
        "output": str(output),
        "clips": len(clip_summaries),
        "frames": sum(item["sourceFrames"] for item in clip_summaries),
        "canvasPx": list(OUTPUT_CANVAS),
        "baseHeightPt": 150.0,
        "groundYPx": OUTPUT_GROUND_Y,
        "bytes": sum(path.stat().st_size for path in output.rglob("*") if path.is_file()),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
