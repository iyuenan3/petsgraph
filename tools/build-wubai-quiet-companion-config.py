#!/usr/bin/env python3
"""Assemble the pinned schema 0.2 Wubai quiet-companion preview source."""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
BASE_CONFIG = ROOT / "workspaces/wubai-private/runtime-records/wubai-basic-behavior-v0.3-source.json"
CANDIDATES = "workspaces/wubai-private/runtime-records/quiet-companion-candidates"
INTERNAL_STATUS = "internal-runtime-candidate-passed-awaiting-Maxwell-and-runtime-chain"
COMPILE_CANVAS = (960, 736)
LEGACY_CANVAS_HEIGHT = 640
LEGACY_CANVAS_TOP = COMPILE_CANVAS[1] - LEGACY_CANVAS_HEIGHT

NODE_DISPLAY_NAMES = {
    "rest.prone.left": "趴卧",
    "rest.side-curled.left": "左侧蜷卧",
    "rest.side-stretched.left": "左侧伸展",
    "rest.supine.left": "仰卧",
    "rest.curled-supine.left": "蜷缩仰卧",
    "rest.semi-supine.left": "松散半仰卧",
    "rest.sleeping-loaf.left": "睡眠香箱",
    "gateway.loaf.legacy.left": "普通香箱过渡",
    "sit.front.floor": "正面坐好",
    "gateway.pillow.b": "靠枕过渡",
    "rest.pillow.head-on": "头趴枕头",
    "rest.pillow.compact-semi-supine": "紧凑半仰卧",
    "rest.pillow.top-curled": "整身蜷睡",
    "sit.front.pillow": "枕边正面坐好",
}


def load_builder():
    path = ROOT / "tools/build-prototype-package.py"
    spec = importlib.util.spec_from_file_location("petsgraph_package_builder", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load package builder: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BUILDER = load_builder()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--created-at", default="2026-08-10T09:00:00+08:00")
    parser.add_argument("--version", default="0.2.0-quiet-companion-preview.1")
    return parser.parse_args()


def load(path: str | Path) -> dict[str, Any]:
    resolved = path if isinstance(path, Path) else ROOT / path
    return json.loads(resolved.read_text(encoding="utf-8"))


def sha256(path: str | Path) -> str:
    resolved = path if isinstance(path, Path) else ROOT / path
    value = hashlib.sha256()
    with resolved.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def frame_facts(source: str) -> tuple[int, str, tuple[int, int]]:
    path = ROOT / source
    frames = sorted(path.glob("frame-*.png"))
    if not frames:
        raise RuntimeError(f"no frames: {source}")
    expected = [f"frame-{index:03d}.png" for index in range(len(frames))]
    if [frame.name for frame in frames] != expected:
        raise RuntimeError(f"non-contiguous frame sequence: {source}")
    return len(frames), BUILDER.ordered_sequence_digest(frames), Image.open(frames[0]).size


def centered_transform(size: tuple[int, int], extra: dict[str, Any] | None = None) -> dict[str, Any]:
    transform = copy.deepcopy(extra or {})
    output_width = int(transform.get("cropPx", [0, 0, size[0], size[1]])[2])
    output_height = int(transform.get("cropPx", [0, 0, size[0], size[1]])[3])
    if output_height not in (LEGACY_CANVAS_HEIGHT, COMPILE_CANVAS[1]) or output_width > COMPILE_CANVAS[0]:
        raise RuntimeError(
            f"source cannot be placed on {COMPILE_CANVAS[0]}x{COMPILE_CANVAS[1]} canvas: "
            f"{size}, {transform}"
        )
    transform["compilePlacementPx"] = [
        (COMPILE_CANVAS[0] - output_width) // 2,
        LEGACY_CANVAS_TOP if output_height == LEGACY_CANVAS_HEIGHT else 0,
    ]
    return transform


def approved_clip_from_base(
    base: dict[str, Any],
    clip_id: str,
    *,
    entry: str | None = None,
    exit: str | None = None,
    preload: list[str] | None = None,
) -> dict[str, Any]:
    clip = copy.deepcopy(next(item for item in base["clips"] if item["id"] == clip_id))
    clip["approvedRecipeSha256"] = sha256(clip["approvedRecipe"])
    source_size = tuple(int(value) for value in clip.get("sourceCanvasPx", base["sourceCanvasPx"]))
    clip["transform"] = centered_transform(source_size, clip.get("transform"))
    if entry is not None:
        clip["entryPose"] = entry
    if exit is not None:
        clip["exitPose"] = exit
    if preload is not None:
        clip["preloadHints"] = preload
    return clip


def approved_segment_clip(
    *,
    clip_id: str,
    source: str,
    recipe: str,
    clip_type: str,
    facing: str,
    entry: str,
    exit: str,
    safe_exit: list[int],
    preload: list[str],
    transform: dict[str, Any],
) -> dict[str, Any]:
    frames, digest, size = frame_facts(source)
    data = load(recipe)
    status = data.get("approval", {}).get("status") or data.get("status")
    subject = data.get("subjectId") or data.get("edgeId")
    return {
        "id": clip_id,
        "type": clip_type,
        "facing": facing,
        "entryPose": entry,
        "exitPose": exit,
        "source": source,
        "sourceCanvasPx": list(size),
        "frameCount": frames,
        "fps": 24,
        "sourceSequenceDigest": digest,
        "safeExitFrames": safe_exit,
        "preloadHints": preload,
        "transform": centered_transform(size, transform),
        "motion": {"kind": "stationary"},
        "rootMotionStatus": "strictly-zero",
        "approvalStatus": status,
        "approvalSubjectId": subject,
        "approvedRecipe": recipe,
        "approvedRecipeSha256": sha256(recipe),
        "normalization": "one fixed compiled-copy transform; no per-frame repositioning",
    }


def candidate_clip(
    *,
    clip_id: str,
    recipe: str,
    clip_type: str,
    facing: str,
    entry: str,
    exit: str,
    safe_exit: list[int],
    preload: list[str],
    transform: dict[str, Any] | None = None,
    motion: dict[str, Any] | None = None,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    data = load(recipe)
    fact = data["factSource"]
    recipe_path = ROOT / recipe
    source = (recipe_path.parent / fact["path"]).resolve(strict=True)
    source.relative_to(ROOT)
    source_relative = source.relative_to(ROOT).as_posix()
    frames, digest, size = frame_facts(source_relative)
    if frames != int(data["selection"]["selectedFrames"]):
        raise RuntimeError(f"candidate frame count mismatch: {clip_id}")
    if digest != fact["orderedSequenceDigest"]:
        raise RuntimeError(f"candidate sequence digest mismatch: {clip_id}")
    status = data.get("approval", {}).get("status") or data["status"]
    subject = data.get("subjectId") or data.get("edgeId") or data.get("clipId")
    config = {
        "id": clip_id,
        "type": clip_type,
        "facing": facing,
        "entryPose": entry,
        "exitPose": exit,
        "source": source_relative,
        "sourceCanvasPx": list(size),
        "frameCount": frames,
        "fps": float(data["selection"].get("fps", 24)),
        "sourceSequenceDigest": digest,
        "safeExitFrames": safe_exit,
        "preloadHints": preload,
        "transform": centered_transform(size, transform),
        "motion": motion or {"kind": "stationary"},
        "rootMotionStatus": (
            "scene-transition-calibrated-awaiting-human-desktop-review"
            if (motion or {}).get("kind") != "stationary" and motion is not None
            else "strictly-zero"
        ),
        "approvalStatus": status,
        "approvalSubjectId": subject,
        "candidateRecipe": recipe,
        "candidateRecipeSha256": sha256(recipe),
        "normalization": "one fixed compiled-copy transform; no per-frame repositioning",
    }
    if metadata is not None:
        config["metadata"] = metadata
    return config


def node(
    node_id: str,
    posture: str,
    orientation: str,
    scene: str,
    role: str,
    loop_clip: str,
    *,
    autonomous: bool,
) -> dict[str, Any]:
    return {
        "id": node_id,
        "displayName": NODE_DISPLAY_NAMES[node_id],
        "posture": posture,
        "orientation": orientation,
        "grounded": True,
        "stability": "stable",
        "scene": scene,
        "role": role,
        "autonomousEligible": autonomous,
        "props": ["pillow"] if scene == "pillow" else [],
        "loopClip": loop_clip,
    }


def edge(
    edge_id: str,
    source: str,
    target: str,
    clip: str,
    *,
    scene_change: str | None = None,
) -> dict[str, Any]:
    value = {
        "id": edge_id,
        "from": source,
        "to": target,
        "clip": clip,
        "kind": "scene-transition" if scene_change else "transition",
        "interruptPolicy": "finish-before-retarget",
        "targetStartFrame": 0,
    }
    if scene_change is not None:
        value["sceneChange"] = scene_change
    return value


PROP = {"pillow": [410, 346, 410, 315]}
PILLOW_META = {
    "gateway": {"petBoundsPx": [105, 211, 520, 460], "propBoundsPx": PROP, "petHitEllipsePx": [115, 221, 435, 405]},
    "head": {"petBoundsPx": [80, 196, 580, 480], "propBoundsPx": PROP, "petHitEllipsePx": [90, 211, 500, 420]},
    "compact": {"petBoundsPx": [35, 201, 625, 465], "propBoundsPx": PROP, "petHitEllipsePx": [50, 216, 535, 405]},
    "top": {"petBoundsPx": [120, 161, 640, 500], "propBoundsPx": PROP, "petHitEllipsePx": [145, 176, 540, 420]},
    "sit": {"petBoundsPx": [120, 186, 405, 490], "propBoundsPx": PROP, "petHitEllipsePx": [130, 196, 360, 455]},
    "wide": {"petBoundsPx": [20, 166, 700, 520], "propBoundsPx": PROP, "petHitEllipsePx": [35, 181, 600, 465]},
}


def main() -> None:
    args = parse_args()
    base = BUILDER.load_config(ROOT, BASE_CONFIG)
    clips: list[dict[str, Any]] = []

    # Human-approved floor facts reused at the global floor ground.
    clips.extend([
        approved_clip_from_base(base, "prone-left-to-side-curled-left-v1", preload=["side-curled-left-loop-v1"]),
        approved_clip_from_base(base, "side-curled-left-loop-v1", preload=["side-curled-left-to-prone-left-v1", "side-curled-left-to-side-stretched-left-v1", "side-curled-left-to-supine-left-v1", "side-curled-left-to-sit-front-v2"]),
        approved_clip_from_base(base, "side-curled-left-to-prone-left-v1", preload=["prone-left-long-loop-v1"]),
        approved_clip_from_base(base, "side-stretched-left-loop-v1", preload=["side-stretched-left-to-side-curled-left-v1", "side-stretched-left-to-supine-left-v1", "side-stretched-left-to-sit-front-v2"]),
        approved_clip_from_base(base, "side-curled-left-to-side-stretched-left-v1", preload=["side-stretched-left-loop-v1"]),
        approved_clip_from_base(base, "side-stretched-left-to-side-curled-left-v1", preload=["side-curled-left-loop-v1"]),
        approved_clip_from_base(base, "supine-left-loop-v1", preload=["supine-left-to-side-curled-left-v1", "supine-left-to-side-stretched-left-v1", "supine-left-to-curled-supine-left-v1", "supine-left-to-semi-supine-left-v1", "supine-left-to-sit-front-v3"]),
        approved_clip_from_base(base, "side-curled-left-to-supine-left-v1", preload=["supine-left-loop-v1"]),
        approved_clip_from_base(base, "supine-left-to-side-curled-left-v1", preload=["side-curled-left-loop-v1"]),
        approved_clip_from_base(base, "side-stretched-left-to-supine-left-v1", preload=["supine-left-loop-v1"]),
        approved_clip_from_base(base, "supine-left-to-side-stretched-left-v1", preload=["side-stretched-left-loop-v1"]),
        approved_clip_from_base(base, "sit-front-loop-v1", entry="sit.front.floor", exit="sit.front.floor", preload=["sit-front-to-prone-left-v3"]),
        approved_clip_from_base(base, "sit-front-to-prone-left-v3", entry="sit.front.floor", exit="rest.prone.left", preload=["prone-left-long-loop-v1"]),
        approved_clip_from_base(base, "prone-left-to-sit-front-v1", entry="rest.prone.left", exit="sit.front.floor", preload=["sit-front-loop-v1"]),
        approved_clip_from_base(base, "prone-left-to-loaf-left-v1", exit="gateway.loaf.legacy.left", preload=["loaf-left-loop-v1"]),
        approved_clip_from_base(base, "loaf-left-loop-v1", entry="gateway.loaf.legacy.left", exit="gateway.loaf.legacy.left", preload=["loaf-left-to-prone-left-v1", "legacy-loaf-left-to-sleeping-loaf-left-v1"]),
        approved_clip_from_base(base, "loaf-left-to-prone-left-v1", entry="gateway.loaf.legacy.left", preload=["prone-left-long-loop-v1"]),
    ])

    curled_root = "workspaces/wubai-private/actions/supine-to-curled-supine-to-supine/v1/qa/graph-candidate-v1/segments"
    clips.extend([
        approved_segment_clip(clip_id="supine-left-to-curled-supine-left-v1", source=f"{curled_root}/supine-to-curled-supine/frames", recipe=f"{curled_root}/supine-to-curled-supine/approved-recipe.json", clip_type="transition", facing="left", entry="rest.supine.left", exit="rest.curled-supine.left", safe_exit=[], preload=["curled-supine-left-loop-v1"], transform={"translatePx": [0, 92]}),
        approved_segment_clip(clip_id="curled-supine-left-loop-v1", source=f"{curled_root}/curled-supine-loop/frames", recipe=f"{curled_root}/curled-supine-loop/approved-recipe.json", clip_type="loop", facing="left", entry="rest.curled-supine.left", exit="rest.curled-supine.left", safe_exit=[49], preload=["curled-supine-left-to-supine-left-v1", "curled-supine-left-to-sit-front-v1"], transform={"translatePx": [0, 92]}),
        approved_segment_clip(clip_id="curled-supine-left-to-supine-left-v1", source=f"{curled_root}/curled-supine-to-supine/frames", recipe=f"{curled_root}/curled-supine-to-supine/approved-recipe.json", clip_type="transition", facing="left", entry="rest.curled-supine.left", exit="rest.supine.left", safe_exit=[], preload=["supine-left-loop-v1"], transform={"translatePx": [0, 92]}),
    ])

    # Candidate floor improvements and missing direct wake paths.
    cr = lambda name: f"{CANDIDATES}/{name}.json"
    clips.extend([
        candidate_clip(clip_id="prone-left-long-loop-v1", recipe=cr("prone-left-long-loop-v1"), clip_type="loop", facing="left", entry="rest.prone.left", exit="rest.prone.left", safe_exit=[235], preload=["prone-left-to-side-curled-left-v1", "prone-left-to-loaf-left-v1", "prone-left-to-sit-front-v1", "prone-left-to-pillow-gateway-b-v18"]),
        candidate_clip(clip_id="supine-left-to-semi-supine-left-v1", recipe=cr("supine-to-semi-supine-left-v1"), clip_type="transition", facing="left", entry="rest.supine.left", exit="rest.semi-supine.left", safe_exit=[], preload=["semi-supine-left-loop-v1"], transform={"translatePx": [0, 92]}),
        candidate_clip(clip_id="semi-supine-left-loop-v1", recipe=cr("semi-supine-left-loop-v1"), clip_type="loop", facing="left", entry="rest.semi-supine.left", exit="rest.semi-supine.left", safe_exit=[49], preload=["semi-supine-left-to-supine-left-v1", "semi-supine-left-to-sit-front-v2"], transform={"translatePx": [0, 92]}),
        candidate_clip(clip_id="semi-supine-left-to-supine-left-v1", recipe=cr("semi-supine-left-to-supine-left-v1"), clip_type="transition", facing="left", entry="rest.semi-supine.left", exit="rest.supine.left", safe_exit=[], preload=["supine-left-loop-v1"], transform={"translatePx": [0, 92]}),
        candidate_clip(clip_id="sleeping-loaf-left-loop-v1", recipe=cr("sleeping-loaf-left-loop-v1"), clip_type="loop", facing="left", entry="rest.sleeping-loaf.left", exit="rest.sleeping-loaf.left", safe_exit=[192], preload=["sleeping-loaf-left-to-legacy-loaf-left-v1", "sleeping-loaf-left-to-sit-front-v1"], transform={"translatePx": [0, 92]}),
        candidate_clip(clip_id="legacy-loaf-left-to-sleeping-loaf-left-v1", recipe=cr("legacy-loaf-left-to-sleeping-loaf-left-v1"), clip_type="transition", facing="left", entry="gateway.loaf.legacy.left", exit="rest.sleeping-loaf.left", safe_exit=[], preload=["sleeping-loaf-left-loop-v1"], transform={"translatePx": [0, 92]}),
        candidate_clip(clip_id="sleeping-loaf-left-to-legacy-loaf-left-v1", recipe=cr("sleeping-loaf-left-to-legacy-loaf-left-v1"), clip_type="transition", facing="left", entry="rest.sleeping-loaf.left", exit="gateway.loaf.legacy.left", safe_exit=[], preload=["loaf-left-loop-v1"], transform={"translatePx": [0, 92]}),
        candidate_clip(clip_id="sleeping-loaf-left-to-sit-front-v1", recipe=cr("sleeping-loaf-left-to-sit-front-v1"), clip_type="transition", facing="left", entry="rest.sleeping-loaf.left", exit="sit.front.floor", safe_exit=[], preload=["sit-front-loop-v1"]),
        candidate_clip(clip_id="side-curled-left-to-sit-front-v2", recipe=cr("side-curled-left-to-sit-front-v2"), clip_type="transition", facing="left", entry="rest.side-curled.left", exit="sit.front.floor", safe_exit=[], preload=["sit-front-loop-v1"]),
        candidate_clip(clip_id="side-stretched-left-to-sit-front-v2", recipe=cr("side-stretched-left-to-sit-front-v2"), clip_type="transition", facing="left", entry="rest.side-stretched.left", exit="sit.front.floor", safe_exit=[], preload=["sit-front-loop-v1"]),
        candidate_clip(clip_id="supine-left-to-sit-front-v3", recipe=cr("supine-left-to-sit-front-v3"), clip_type="transition", facing="left", entry="rest.supine.left", exit="sit.front.floor", safe_exit=[], preload=["sit-front-loop-v1"]),
        candidate_clip(clip_id="curled-supine-left-to-sit-front-v1", recipe=cr("curled-supine-left-to-sit-front-v1"), clip_type="transition", facing="left", entry="rest.curled-supine.left", exit="sit.front.floor", safe_exit=[], preload=["sit-front-loop-v1"]),
        candidate_clip(clip_id="semi-supine-left-to-sit-front-v2", recipe="workspaces/wubai-private/actions/semi-supine-left-to-sit-front/v2/candidate-recipe.json", clip_type="transition", facing="left", entry="rest.semi-supine.left", exit="sit.front.floor", safe_exit=[], preload=["sit-front-loop-v1"]),
    ])

    # Legacy 640px-tall facts are padded 96px above on the global 960x736 canvas.
    crop960 = {"cropPx": [0, 144, 960, 640]}
    compact640 = {"translatePx": [0, 16]}
    crop768 = {"cropPx": [0, 48, 768, 640]}
    clips.extend([
        candidate_clip(clip_id="pillow-gateway-b-loop-v1", recipe=cr("pillow-gateway-b-loop-v1"), clip_type="loop", facing="left", entry="gateway.pillow.b", exit="gateway.pillow.b", safe_exit=[23], preload=["pillow-gateway-b-to-head-on-pillow-v1", "pillow-gateway-b-to-compact-semi-supine-v1", "pillow-gateway-b-to-top-curled-v1", "pillow-gateway-b-to-sit-front-v2", "pillow-gateway-b-to-prone-left-v5"], transform=crop960, metadata=PILLOW_META["gateway"]),
        candidate_clip(clip_id="pillow-gateway-b-to-head-on-pillow-v1", recipe=cr("pillow-gateway-b-to-head-on-pillow-v1"), clip_type="transition", facing="left", entry="gateway.pillow.b", exit="rest.pillow.head-on", safe_exit=[], preload=["head-on-pillow-loop-v1"], transform=crop960, metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="head-on-pillow-loop-v1", recipe=cr("head-on-pillow-loop-v1"), clip_type="loop", facing="left", entry="rest.pillow.head-on", exit="rest.pillow.head-on", safe_exit=[119], preload=["head-on-pillow-to-pillow-gateway-b-v1", "head-on-pillow-to-sit-front-v1", "head-on-pillow-to-compact-semi-supine-pillow-v1"], transform=crop960, metadata=PILLOW_META["head"]),
        candidate_clip(clip_id="head-on-pillow-to-pillow-gateway-b-v1", recipe=cr("head-on-pillow-to-pillow-gateway-b-v1"), clip_type="transition", facing="left", entry="rest.pillow.head-on", exit="gateway.pillow.b", safe_exit=[], preload=["pillow-gateway-b-loop-v1"], transform=crop960, metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="pillow-gateway-b-to-compact-semi-supine-v1", recipe=cr("pillow-gateway-b-to-compact-semi-supine-v1"), clip_type="transition", facing="left", entry="gateway.pillow.b", exit="rest.pillow.compact-semi-supine", safe_exit=[], preload=["compact-semi-supine-pillow-loop-v1"], transform=compact640, metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="compact-semi-supine-pillow-loop-v1", recipe=cr("compact-semi-supine-pillow-loop-v1"), clip_type="loop", facing="left", entry="rest.pillow.compact-semi-supine", exit="rest.pillow.compact-semi-supine", safe_exit=[49], preload=["compact-semi-supine-pillow-to-gateway-b-v1", "compact-semi-supine-pillow-to-sit-front-v2", "compact-semi-supine-pillow-to-head-on-pillow-v1"], transform=compact640, metadata=PILLOW_META["compact"]),
        candidate_clip(clip_id="compact-semi-supine-pillow-to-gateway-b-v1", recipe=cr("compact-semi-supine-pillow-to-gateway-b-v1"), clip_type="transition", facing="left", entry="rest.pillow.compact-semi-supine", exit="gateway.pillow.b", safe_exit=[], preload=["pillow-gateway-b-loop-v1"], transform=compact640, metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="pillow-gateway-b-to-top-curled-v1", recipe=cr("pillow-gateway-b-to-top-curled-v1"), clip_type="transition", facing="left", entry="gateway.pillow.b", exit="rest.pillow.top-curled", safe_exit=[], preload=["pillow-top-curled-loop-v1"], transform=crop768, metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="pillow-top-curled-loop-v1", recipe=cr("pillow-top-curled-loop-v1"), clip_type="loop", facing="left", entry="rest.pillow.top-curled", exit="rest.pillow.top-curled", safe_exit=[49], preload=["pillow-top-curled-to-gateway-b-v2", "pillow-top-curled-to-sit-front-v1"], transform=crop768, metadata=PILLOW_META["top"]),
        candidate_clip(clip_id="pillow-top-curled-to-gateway-b-v2", recipe=cr("pillow-top-curled-to-gateway-b-v2"), clip_type="transition", facing="left", entry="rest.pillow.top-curled", exit="gateway.pillow.b", safe_exit=[], preload=["pillow-gateway-b-loop-v1"], transform=crop960, metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="pillow-sit-front-loop-v1", recipe="workspaces/wubai-private/actions/pillow-sit-front-loop/v1/candidate-recipe.json", clip_type="loop", facing="front", entry="sit.front.pillow", exit="sit.front.pillow", safe_exit=[144], preload=["pillow-sit-front-to-pillow-gateway-b-v1"], metadata=PILLOW_META["sit"]),
        candidate_clip(clip_id="pillow-gateway-b-to-sit-front-v2", recipe="workspaces/wubai-private/actions/pillow-gateway-b-to-sit-front/v2/candidate-recipe.json", clip_type="transition", facing="front", entry="gateway.pillow.b", exit="sit.front.pillow", safe_exit=[], preload=["pillow-sit-front-loop-v1"], metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="pillow-sit-front-to-pillow-gateway-b-v1", recipe="workspaces/wubai-private/actions/pillow-sit-front-to-pillow-gateway-b/v1/candidate-recipe.json", clip_type="transition", facing="left", entry="sit.front.pillow", exit="gateway.pillow.b", safe_exit=[], preload=["pillow-gateway-b-loop-v1"], metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="head-on-pillow-to-sit-front-v1", recipe="workspaces/wubai-private/actions/head-on-pillow-to-sit-front/v1/candidate-recipe.json", clip_type="transition", facing="front", entry="rest.pillow.head-on", exit="sit.front.pillow", safe_exit=[], preload=["pillow-sit-front-loop-v1"], metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="compact-semi-supine-pillow-to-sit-front-v2", recipe="workspaces/wubai-private/actions/compact-semi-supine-pillow-to-sit-front/v2/candidate-recipe.json", clip_type="transition", facing="front", entry="rest.pillow.compact-semi-supine", exit="sit.front.pillow", safe_exit=[], preload=["pillow-sit-front-loop-v1"], metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="pillow-top-curled-to-sit-front-v1", recipe="workspaces/wubai-private/actions/pillow-top-curled-to-sit-front/v1/candidate-recipe.json", clip_type="transition", facing="front", entry="rest.pillow.top-curled", exit="sit.front.pillow", safe_exit=[], preload=["pillow-sit-front-loop-v1"], metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="head-on-pillow-to-compact-semi-supine-pillow-v1", recipe="workspaces/wubai-private/actions/head-on-pillow-to-compact-semi-supine-pillow/v1/candidate-recipe.json", clip_type="transition", facing="left", entry="rest.pillow.head-on", exit="rest.pillow.compact-semi-supine", safe_exit=[], preload=["compact-semi-supine-pillow-loop-v1"], metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="compact-semi-supine-pillow-to-head-on-pillow-v1", recipe="workspaces/wubai-private/actions/compact-semi-supine-pillow-to-head-on-pillow/v1/candidate-recipe.json", clip_type="transition", facing="left", entry="rest.pillow.compact-semi-supine", exit="rest.pillow.head-on", safe_exit=[], preload=["head-on-pillow-loop-v1"], metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="pillow-gateway-b-to-prone-left-v5", recipe="workspaces/wubai-private/actions/pillow-gateway-b-to-prone-left/v5-expanded736/candidate-recipe.json", clip_type="transition", facing="left", entry="gateway.pillow.b", exit="rest.prone.left", safe_exit=[], preload=["prone-left-long-loop-v1"], motion={"kind": "windowed-smooth-distance", "startSeconds": 3.333333, "durationSeconds": 5.666667, "distancePt": 35.625}, metadata=PILLOW_META["wide"]),
        candidate_clip(clip_id="prone-left-to-pillow-gateway-b-v18", recipe="workspaces/wubai-private/actions/prone-left-to-pillow-gateway-b/v18-expanded736/candidate-recipe.json", clip_type="transition", facing="right", entry="rest.prone.left", exit="gateway.pillow.b", safe_exit=[], preload=["pillow-gateway-b-loop-v1"], motion={"kind": "windowed-smooth-distance", "startSeconds": 4.0, "durationSeconds": 5.166667, "distancePt": 35.625}, metadata=PILLOW_META["wide"]),
    ])

    nodes = [
        node("rest.prone.left", "prone", "left", "floor", "dwell", "prone-left-long-loop-v1", autonomous=True),
        node("rest.side-curled.left", "side-curled", "left", "floor", "dwell", "side-curled-left-loop-v1", autonomous=True),
        node("rest.side-stretched.left", "side-stretched", "left", "floor", "dwell", "side-stretched-left-loop-v1", autonomous=True),
        node("rest.supine.left", "supine", "left", "floor", "dwell", "supine-left-loop-v1", autonomous=True),
        node("rest.curled-supine.left", "curled-supine", "left", "floor", "dwell", "curled-supine-left-loop-v1", autonomous=True),
        node("rest.semi-supine.left", "semi-supine", "left", "floor", "dwell", "semi-supine-left-loop-v1", autonomous=True),
        node("rest.sleeping-loaf.left", "sleeping-loaf", "left", "floor", "dwell", "sleeping-loaf-left-loop-v1", autonomous=True),
        node("gateway.loaf.legacy.left", "loaf", "left", "floor", "gateway", "loaf-left-loop-v1", autonomous=False),
        node("sit.front.floor", "sit", "front", "floor", "interaction", "sit-front-loop-v1", autonomous=False),
        node("gateway.pillow.b", "pillow-lean", "left", "pillow", "gateway", "pillow-gateway-b-loop-v1", autonomous=False),
        node("rest.pillow.head-on", "head-on-pillow", "left", "pillow", "dwell", "head-on-pillow-loop-v1", autonomous=True),
        node("rest.pillow.compact-semi-supine", "compact-semi-supine", "left", "pillow", "dwell", "compact-semi-supine-pillow-loop-v1", autonomous=True),
        node("rest.pillow.top-curled", "top-curled", "left", "pillow", "dwell", "pillow-top-curled-loop-v1", autonomous=True),
        node("sit.front.pillow", "sit", "front", "pillow", "interaction", "pillow-sit-front-loop-v1", autonomous=False),
    ]

    edges = [
        edge("prone-left-to-side-curled-left", "rest.prone.left", "rest.side-curled.left", "prone-left-to-side-curled-left-v1"),
        edge("side-curled-left-to-prone-left", "rest.side-curled.left", "rest.prone.left", "side-curled-left-to-prone-left-v1"),
        edge("side-curled-left-to-side-stretched-left", "rest.side-curled.left", "rest.side-stretched.left", "side-curled-left-to-side-stretched-left-v1"),
        edge("side-stretched-left-to-side-curled-left", "rest.side-stretched.left", "rest.side-curled.left", "side-stretched-left-to-side-curled-left-v1"),
        edge("side-curled-left-to-supine-left", "rest.side-curled.left", "rest.supine.left", "side-curled-left-to-supine-left-v1"),
        edge("supine-left-to-side-curled-left", "rest.supine.left", "rest.side-curled.left", "supine-left-to-side-curled-left-v1"),
        edge("side-stretched-left-to-supine-left", "rest.side-stretched.left", "rest.supine.left", "side-stretched-left-to-supine-left-v1"),
        edge("supine-left-to-side-stretched-left", "rest.supine.left", "rest.side-stretched.left", "supine-left-to-side-stretched-left-v1"),
        edge("supine-left-to-curled-supine-left", "rest.supine.left", "rest.curled-supine.left", "supine-left-to-curled-supine-left-v1"),
        edge("curled-supine-left-to-supine-left", "rest.curled-supine.left", "rest.supine.left", "curled-supine-left-to-supine-left-v1"),
        edge("supine-left-to-semi-supine-left", "rest.supine.left", "rest.semi-supine.left", "supine-left-to-semi-supine-left-v1"),
        edge("semi-supine-left-to-supine-left", "rest.semi-supine.left", "rest.supine.left", "semi-supine-left-to-supine-left-v1"),
        edge("prone-left-to-legacy-loaf-left", "rest.prone.left", "gateway.loaf.legacy.left", "prone-left-to-loaf-left-v1"),
        edge("legacy-loaf-left-to-prone-left", "gateway.loaf.legacy.left", "rest.prone.left", "loaf-left-to-prone-left-v1"),
        edge("legacy-loaf-left-to-sleeping-loaf-left", "gateway.loaf.legacy.left", "rest.sleeping-loaf.left", "legacy-loaf-left-to-sleeping-loaf-left-v1"),
        edge("sleeping-loaf-left-to-legacy-loaf-left", "rest.sleeping-loaf.left", "gateway.loaf.legacy.left", "sleeping-loaf-left-to-legacy-loaf-left-v1"),
        edge("prone-left-to-sit-front", "rest.prone.left", "sit.front.floor", "prone-left-to-sit-front-v1"),
        edge("side-curled-left-to-sit-front", "rest.side-curled.left", "sit.front.floor", "side-curled-left-to-sit-front-v2"),
        edge("side-stretched-left-to-sit-front", "rest.side-stretched.left", "sit.front.floor", "side-stretched-left-to-sit-front-v2"),
        edge("supine-left-to-sit-front", "rest.supine.left", "sit.front.floor", "supine-left-to-sit-front-v3"),
        edge("curled-supine-left-to-sit-front", "rest.curled-supine.left", "sit.front.floor", "curled-supine-left-to-sit-front-v1"),
        edge("semi-supine-left-to-sit-front", "rest.semi-supine.left", "sit.front.floor", "semi-supine-left-to-sit-front-v2"),
        edge("sleeping-loaf-left-to-sit-front", "rest.sleeping-loaf.left", "sit.front.floor", "sleeping-loaf-left-to-sit-front-v1"),
        edge("sit-front-to-prone-left", "sit.front.floor", "rest.prone.left", "sit-front-to-prone-left-v3"),
        edge("pillow-gateway-b-to-head-on-pillow", "gateway.pillow.b", "rest.pillow.head-on", "pillow-gateway-b-to-head-on-pillow-v1"),
        edge("head-on-pillow-to-pillow-gateway-b", "rest.pillow.head-on", "gateway.pillow.b", "head-on-pillow-to-pillow-gateway-b-v1"),
        edge("pillow-gateway-b-to-compact-semi-supine", "gateway.pillow.b", "rest.pillow.compact-semi-supine", "pillow-gateway-b-to-compact-semi-supine-v1"),
        edge("compact-semi-supine-pillow-to-gateway-b", "rest.pillow.compact-semi-supine", "gateway.pillow.b", "compact-semi-supine-pillow-to-gateway-b-v1"),
        edge("pillow-gateway-b-to-top-curled", "gateway.pillow.b", "rest.pillow.top-curled", "pillow-gateway-b-to-top-curled-v1"),
        edge("pillow-top-curled-to-gateway-b", "rest.pillow.top-curled", "gateway.pillow.b", "pillow-top-curled-to-gateway-b-v2"),
        edge("head-on-pillow-to-compact-semi-supine", "rest.pillow.head-on", "rest.pillow.compact-semi-supine", "head-on-pillow-to-compact-semi-supine-pillow-v1"),
        edge("compact-semi-supine-to-head-on-pillow", "rest.pillow.compact-semi-supine", "rest.pillow.head-on", "compact-semi-supine-pillow-to-head-on-pillow-v1"),
        edge("pillow-gateway-b-to-sit-front", "gateway.pillow.b", "sit.front.pillow", "pillow-gateway-b-to-sit-front-v2"),
        edge("head-on-pillow-to-sit-front", "rest.pillow.head-on", "sit.front.pillow", "head-on-pillow-to-sit-front-v1"),
        edge("compact-semi-supine-pillow-to-sit-front", "rest.pillow.compact-semi-supine", "sit.front.pillow", "compact-semi-supine-pillow-to-sit-front-v2"),
        edge("pillow-top-curled-to-sit-front", "rest.pillow.top-curled", "sit.front.pillow", "pillow-top-curled-to-sit-front-v1"),
        edge("pillow-sit-front-to-gateway-b", "sit.front.pillow", "gateway.pillow.b", "pillow-sit-front-to-pillow-gateway-b-v1"),
        edge("prone-left-to-pillow-gateway-b", "rest.prone.left", "gateway.pillow.b", "prone-left-to-pillow-gateway-b-v18", scene_change="floor-to-pillow"),
        edge("pillow-gateway-b-to-prone-left", "gateway.pillow.b", "rest.prone.left", "pillow-gateway-b-to-prone-left-v5", scene_change="pillow-to-floor"),
    ]

    material_units = [
        {
            "clipId": clip["id"],
            "approvalStatus": clip["approvalStatus"],
            "humanApproved": str(clip["approvalStatus"]).startswith("human-"),
            "recipe": clip.get("approvedRecipe") or clip.get("candidateRecipe"),
            "recipeSha256": clip.get("approvedRecipeSha256") or clip.get("candidateRecipeSha256"),
            "sourceSequenceDigest": clip["sourceSequenceDigest"],
        }
        for clip in clips
    ]
    config = {
        "schema": 1,
        "schemaVersion": "0.2.0",
        "package": {
            "id": "wubai-quiet-companion-preview",
            "version": args.version,
            "createdAt": args.created_at,
        },
        "pet": {
            "id": "wubai",
            "displayName": "李五百",
            "species": "cat",
            "identityStyle": "faithful-real-pet",
        },
        "sourceCanvasPx": [640, 640],
        "compilationCanvasPx": [960, 736],
        "sourcePlacementPx": [160, 96],
        "runtimeCanvasPx": [480, 368],
        "sourceGroundYExclusivePx": 532,
        "compiledGroundYExclusivePx": 628,
        "baseHeightPt": 172.5,
        "defaultNode": "rest.prone.left",
        "environmentProps": [
            {
                "id": "pillow",
                "source": "workspaces/wubai-private/actions/pillow-prop-shared/pillow-only-canonical960-v5.png",
                "sourceCanvasPx": [960, 960],
                "transform": {"cropPx": [0, 144, 960, 640], "compilePlacementPx": [0, 96]},
                "offsetFromFloorOriginPt": [35.625, 0.0],
                "visibility": "embedded",
                "scenes": ["pillow"],
                "layer": "behind-pet",
                "hitTest": "passthrough",
                "candidateManifest": "workspaces/wubai-private/actions/pillow-prop-shared/pillow-only-canonical960-v5-manifest.json",
                "candidateManifestSha256": sha256("workspaces/wubai-private/actions/pillow-prop-shared/pillow-only-canonical960-v5-manifest.json"),
                "status": "internal-generated-prop-candidate-awaiting-Maxwell-and-runtime-chain",
            }
        ],
        "calibration": {
            "status": "scene-transition-root-motion-awaiting-human-desktop-review",
            "method": "window motion uses one positive cumulative profile per native directional scene edge; the planner applies the native clip facing sign",
            "sceneTransitions": {
                "floor-to-pillow": {"clip": "prone-left-to-pillow-gateway-b-v18", "direction": "right", "distancePt": 35.625, "motionFramesInclusive": [96, 220]},
                "pillow-to-floor": {"clip": "pillow-gateway-b-to-prone-left-v5", "direction": "left", "distancePt": 35.625, "motionFramesInclusive": [80, 216]},
            },
        },
        "normalization": {
            "canvas": "one global 960x736 compile canvas downsampled once to a 480x368 runtime copy",
            "groundAnchorPx": {"compile": [480, 628], "runtime": [240, 314]},
            "floor": "640x640 facts use fixed x=160,y=96 placement; only facts whose own recipe declares source ground 440 additionally receive one fixed y=92 translation; the long prone loop remains at visual ground 532 before the shared 96px top pad",
            "sceneEdges": "V18 and V5 already use pinned 960x736 compiled fact sequences, so they receive no additional placement, scale or crop",
            "environmentPillow": "the canonical prop remains integrity-pinned as embedded reference metadata; pillow pixels are carried by the direct-generated clip frames and are never rendered a second time",
            "pillowV9": "640x640 facts use one fixed x=160,y=96 placement plus their declared fixed y=16 content translation",
            "pillowV6": "768x768 facts use one fixed top crop y=48 and x=96,y=96 placement",
            "prohibited": ["per-frame repositioning", "interpolation", "optical flow", "RIFE", "bones", "crossfade", "reverse playback", "runtime mirroring"],
        },
        "behavior": {
            "profile": "quiet-sleep-companion",
            "defaultIntent": "sleep",
            "timing": {
                "strategy": "random-long-tail",
                "parametersStatus": "awaiting-human-30-minute-runtime-review",
                "avoidImmediateRepeat": True,
                "minimumDwellSeconds": 180,
                "medianDwellSeconds": 480,
                "maximumDwellSeconds": 1800,
                "recentHistoryLimit": 2,
                "sameSceneProbability": 0.9,
            },
            "scenePolicy": {
                "floor": {"sticky": True, "gateway": None, "minimumDwellSeconds": 900, "exitCooldownSeconds": 1800},
                "pillow": {"sticky": True, "gateway": "gateway.pillow.b", "minimumDwellSeconds": 1800, "exitCooldownSeconds": 1800},
            },
            "interactions": {
                "petClick": {
                    "sleeping": "wake-to-scene-sit",
                    "sitting": "return-to-scene-sleep",
                    "debounceSeconds": 0.35,
                },
                "desktopClick": "ignore",
                "drag": "direct-manipulation",
            },
        },
        "graph": {"nodes": nodes, "edges": edges},
        "demoSequence": {
            "id": "wubai-quiet-companion-default-sleep",
            "segments": [{"clip": "prone-left-long-loop-v1", "startFrame": 0, "cycles": 1, "repeatForever": True}],
        },
        "clips": clips,
        "materialUnits": material_units,
        "graphConnectivity": {
            "status": "complete-for-preview-awaiting-human-runtime-review",
            "floorDwellNodes": 7,
            "pillowDwellNodes": 3,
            "gatewayNodes": 2,
            "interactionNodes": 2,
            "allDwellNodesHaveDirectSceneSitWake": True,
            "sceneChanges": ["floor-to-pillow", "pillow-to-floor"],
        },
        "runtimeReview": {
            "packageStatus": "awaiting-human-runtime-review",
            "installable": False,
            "approvedRuntimeChains": [],
            "remainingGates": [
                "Maxwell final asset montage review",
                "real desktop pet-click, drag, window-level and scene-motion review",
                "normal and slow screen recordings",
                "at least 30 minutes without crash, disappearance, hard cut, request pile-up or prop jump",
            ],
        },
    }
    output = args.output if args.output.is_absolute() else ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": output.relative_to(ROOT).as_posix(), "clips": len(clips), "nodes": len(nodes), "edges": len(edges), "sha256": sha256(output)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
