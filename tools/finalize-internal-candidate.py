#!/usr/bin/env python3
"""Freeze an internally reviewed strict-edge candidate without claiming human approval."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[1]
INTERNAL_STATUS = "internal-visual-review-passed-awaiting-Maxwell-and-runtime-chain"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("job", type=Path)
    parser.add_argument("--note", action="append", required=True)
    return parser.parse_args()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def sequence_digest(paths: list[Path]) -> str:
    value = hashlib.sha256()
    for path in paths:
        value.update(path.name.encode("utf-8"))
        value.update(b"\0")
        value.update(digest(path).encode("ascii"))
        value.update(b"\n")
    return value.hexdigest()


def write_new(path: Path, value: dict) -> None:
    content = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    if path.exists():
        if path.read_text(encoding="utf-8") != content:
            raise RuntimeError(f"refusing to overwrite existing evidence: {path}")
        return
    path.write_text(content, encoding="utf-8")


def main() -> None:
    args = parse_args()
    job = args.job if args.job.is_absolute() else ROOT / args.job
    job = job.resolve(strict=True)
    job.relative_to(ROOT)
    request = load(job / "request-config.json")
    submission = load(job / "submit-attempt.json")
    result = load(job / "task-result.json")
    report_path = job / "qa" / "candidate-report.json"
    report = load(report_path)
    if not str(report.get("status", "")).startswith("mechanical-pass"):
        raise RuntimeError(f"candidate report is not mechanically eligible: {report.get('status')}")
    if report.get("humanApproved") is not False:
        raise RuntimeError("strict candidate report must remain explicitly not human approved")
    source_video = job / "qa" / report["source"]["path"]
    source_video = source_video.resolve(strict=True)
    downloaded = result["downloaded"]["video"]
    if digest(source_video) != downloaded["sha256"] or digest(source_video) != report["source"]["sha256"]:
        raise RuntimeError("source video hash disagreement")
    fact_source = job / "qa" / "compiled-fixed-crop640-frames"
    frames = sorted(fact_source.glob("frame-*.png"))
    expected = int(report["source"]["frames"])
    if len(frames) != expected:
        raise RuntimeError(f"expected {expected} compiled frames, found {len(frames)}")
    names = [f"frame-{index:03d}.png" for index in range(expected)]
    if [path.name for path in frames] != names:
        raise RuntimeError("compiled candidate is not a contiguous zero-based frame sequence")
    sequence = sequence_digest(frames)
    subject_type = "action" if report["runtimeContract"]["from"] == report["runtimeContract"]["to"] else "edge"
    now = datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(timespec="seconds")
    prompt_path = job / "prompt.md"
    config_path = job / "request-config.json"
    recipe = {
        "schema": 1,
        "createdAt": now,
        "subjectType": subject_type,
        "subjectId": report["edgeId"],
        "variant": request["variant"],
        "status": INTERNAL_STATUS,
        "humanApproved": False,
        "runtimeChainApproved": False,
        "generation": {
            "taskId": result["id"],
            "seed": result["seed"],
            "model": result["model"],
            "resolution": result["resolution"],
            "ratio": result["ratio"],
            "durationSeconds": result["duration"],
            "fps": result["framespersecond"],
            "automaticRetries": submission["automaticRetries"],
            "promptSha256": digest(prompt_path),
            "requestConfigSha256": digest(config_path),
            "references": submission["references"],
            "sourceVideo": {
                "path": source_video.relative_to(job).as_posix(),
                "bytes": source_video.stat().st_size,
                "sha256": digest(source_video),
            },
        },
        "selection": {
            "selectedFrames": expected,
            "fps": report["source"]["fps"],
            "runtimeIndexesInclusive": [0, expected - 1],
        },
        "factSource": {
            "path": fact_source.relative_to(job).as_posix(),
            "frames": expected,
            "orderedSequenceDigest": sequence,
        },
        "runtimeContract": report["runtimeContract"],
        "processing": report["processing"],
        "mechanicalEvidence": {
            "path": report_path.relative_to(job).as_posix(),
            "sha256": digest(report_path),
            "status": report["status"],
            "compiledClip": report["compiledClip"],
            "endpointEvidence": report["endpointEvidence"],
        },
        "internalVisualReview": {
            "status": "passed",
            "notes": args.note,
            "mechanicalLimitAcknowledged": report["mechanicalLimit"],
        },
        "approval": {
            "status": INTERNAL_STATUS,
            "humanApproved": False,
            "runtimeChainApproved": False,
            "remainingGate": "Maxwell visual review of the final asset and real desktop chain",
        },
    }
    recipe_path = job / "candidate-recipe.json"
    write_new(recipe_path, recipe)
    review = {
        "schema": 1,
        "createdAt": now,
        "subjectId": report["edgeId"],
        "variant": request["variant"],
        "status": INTERNAL_STATUS,
        "humanApproved": False,
        "runtimeChainApproved": False,
        "candidateRecipe": {
            "path": "../candidate-recipe.json",
            "sha256": digest(recipe_path),
        },
        "sourceVideo": {
            **recipe["generation"]["sourceVideo"],
            "path": "../" + recipe["generation"]["sourceVideo"]["path"],
        },
        "qa": {
            "candidateReport": {
                "path": "candidate-report.json",
                "sha256": digest(report_path),
            },
            "reviewArtifacts": report["reviewArtifacts"],
        },
        "internalReview": recipe["internalVisualReview"],
        "remainingGate": recipe["approval"]["remainingGate"],
    }
    write_new(job / "qa" / "review-manifest.json", review)
    print(
        json.dumps(
            {
                "candidateRecipe": recipe_path.relative_to(ROOT).as_posix(),
                "sha256": digest(recipe_path),
                "frames": expected,
                "orderedSequenceDigest": sequence,
                "status": INTERNAL_STATUS,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
