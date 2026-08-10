#!/usr/bin/env python3
"""Create an immutable runtime-candidate recipe without altering source evidence."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--clip-id", required=True)
    parser.add_argument("--subject-id", required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--from-node", required=True)
    parser.add_argument("--to-node", required=True)
    parser.add_argument("--fps", type=float, default=24)
    parser.add_argument("--status", required=True)
    parser.add_argument("--evidence", action="append", type=Path, default=[])
    parser.add_argument("--note", action="append", required=True)
    return parser.parse_args()


def sha256(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def sequence_digest(frames: list[Path]) -> str:
    value = hashlib.sha256()
    for frame in frames:
        value.update(frame.name.encode("utf-8"))
        value.update(b"\0")
        value.update(sha256(frame).encode("ascii"))
        value.update(b"\n")
    return value.hexdigest()


def within_root(path: Path) -> Path:
    resolved = path if path.is_absolute() else ROOT / path
    resolved = resolved.resolve(strict=True)
    resolved.relative_to(ROOT)
    return resolved


def main() -> None:
    args = parse_args()
    source = within_root(args.source)
    frames = sorted(source.glob("frame-*.png"))
    if not frames:
        raise RuntimeError(f"no frames in {source}")
    expected_names = [f"frame-{index:03d}.png" for index in range(len(frames))]
    if [frame.name for frame in frames] != expected_names:
        raise RuntimeError("runtime source must be a contiguous zero-based frame sequence")
    output = args.output if args.output.is_absolute() else ROOT / args.output
    output = output.resolve(strict=False)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.parent.relative_to(ROOT)
    evidence = []
    for reference in args.evidence:
        path = within_root(reference)
        evidence.append(
            {
                "path": os.path.relpath(path, output.parent),
                "sha256": sha256(path),
            }
        )
    status = args.status
    recipe = {
        "schema": 1,
        "createdAt": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(timespec="seconds"),
        "subjectType": "action" if args.from_node == args.to_node else "edge",
        "subjectId": args.subject_id,
        "clipId": args.clip_id,
        "status": status,
        "humanApproved": False,
        "runtimeChainApproved": False,
        "selection": {
            "selectedFrames": len(frames),
            "fps": args.fps,
            "runtimeIndexesInclusive": [0, len(frames) - 1],
        },
        "factSource": {
            "path": os.path.relpath(source, output.parent),
            "frames": len(frames),
            "orderedSequenceDigest": sequence_digest(frames),
        },
        "runtimeContract": {
            "from": args.from_node,
            "to": args.to_node,
            "ordinaryAutonomousInterruptible": False,
            "directControlInterruptible": False,
            "targetRuntimeFrame": 0,
        },
        "evidence": evidence,
        "internalReview": {
            "status": "passed",
            "notes": args.note,
        },
        "approval": {
            "status": status,
            "humanApproved": False,
            "runtimeChainApproved": False,
            "remainingGate": "Maxwell visual review of the final candidate and desktop runtime chain",
        },
    }
    content = json.dumps(recipe, ensure_ascii=False, indent=2) + "\n"
    if output.exists() and output.read_text(encoding="utf-8") != content:
        raise RuntimeError(f"refusing to overwrite existing runtime candidate recipe: {output}")
    if not output.exists():
        output.write_text(content, encoding="utf-8")
    print(
        json.dumps(
            {
                "output": output.relative_to(ROOT).as_posix(),
                "sha256": sha256(output),
                "frames": len(frames),
                "orderedSequenceDigest": recipe["factSource"]["orderedSequenceDigest"],
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
