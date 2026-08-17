#!/usr/bin/env python3
"""Audit and remove rejected or superseded private media while preserving records.

The script never removes JSON, prompts, recipes, task IDs, seeds, hashes, or
approval records. An execution must use an audit manifest produced from the
same current filesystem state.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
WUBAI = ROOT / "workspaces/wubai-private"
FEILIU = ROOT / "workspaces/feiliu-private"
AUDIT_DIR = ROOT / "workspaces/cleanup-audits"

MEDIA_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".mp4", ".mov", ".mkv", ".avi", ".webm",
    ".gif", ".webp", ".raw", ".rgba", ".bin", ".heic", ".tiff", ".tif",
}
INPUT_PARTS = {
    "input", "inputs", "input-shared", "input-safe", "input-safe-v2",
    "input-safe-v3", "input-aligned", "references",
}
REJECTION_MARKERS = {
    "rejection.json", "rejection-manifest.json", "internal-rejection.json",
    "internal-rejection-fixed-cyan.json", "failure.json", "local-failure.json",
    "local-submit-failure.json",
}


def under(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def sha256_text(lines: Iterable[str]) -> str:
    digest = hashlib.sha256()
    for line in lines:
        digest.update(line.encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def nearest_job_root(marker: Path, actions_root: Path) -> Path | None:
    cursor = marker.parent
    while cursor != actions_root and under(cursor, actions_root):
        if ((cursor / "task-result.json").is_file()
                or (cursor / "submit-attempt.json").is_file()
                or (cursor / "artifacts").is_dir()):
            return cursor
        cursor = cursor.parent
    return None


def rejected_job_roots() -> list[tuple[Path, str, bool]]:
    result: dict[Path, tuple[str, bool]] = {}
    for private_root in (WUBAI, FEILIU):
        actions_root = private_root / "actions"
        if not actions_root.is_dir():
            continue
        for marker in actions_root.rglob("*.json"):
            if marker.name not in REJECTION_MARKERS:
                continue
            job_root = nearest_job_root(marker, actions_root)
            if job_root is None:
                continue
            if any(job_root.rglob("approved-recipe.json")):
                continue
            result[job_root.resolve()] = (
                f"explicit rejection or failure marker: {rel(marker)}",
                True,
            )
    return [(path, reason, preserve_inputs) for path, (reason, preserve_inputs) in result.items()]


def superseded_derived_roots() -> list[tuple[Path, str, bool]]:
    roots: list[tuple[Path, str, bool]] = []

    feiliu_goal_11 = FEILIU / "goal-2026-08-11"
    keep_goal_11 = {
        "safe-canvas-compile-qa-v3-all-loops",
        "floor-core-chain-safe-canvas-v1.4-stable-matte",
        "node-graph-contract-v1",
        "selected-no-prop-safe-anchors-v23",
        "selected-blanket-safe-anchors-v22",
        "blanket-safe-final-candidates-v2",
        "blanket-matted-safe-reconstruction-seedance2-v22",
        "blanket-safe-strict-loops-seedance2-v24",
        "blanket-ultra-still-loops-seedance2-v25",
        "blanket-supine-pixel-lock-loops-seedance2-v26",
        "user-rerun-semi-supine-knead-v27",
    }
    if feiliu_goal_11.is_dir():
        for child in feiliu_goal_11.iterdir():
            if child.is_dir() and child.name not in keep_goal_11:
                roots.append((child.resolve(), "superseded derived review or compile output", False))

    obsolete_goal_14 = {
        "complete-wide-graph-compile-v1",
        "complete-wide-graph-compile-v2-cat-bed-scale-fixed",
        "random-graph-preview-v1",
        "random-graph-preview-v2-runtime-semantics",
        "transition-rebuild-review-v1.1",
        "transition-rebuild-review-v1.2-cyan-family",
        "transition-rebuild-review-v1.3-boundary-components",
        "transition-rebuild-review-v2-all-new-small-safe",
        "transition-rebuild-review-v3-all-new-final-candidates",
        "transition-rebuild-review-v3.failed-local-exec-window-before-manifest",
        "transition-runtime-compile-v5-all-eight",
        "transition-runtime-compile-v6-wide-canvas-all-eight",
        "transition-runtime-compile-v6-wide-canvas-all-eight.failed-node-canvas-mismatch",
    }
    feiliu_goal_14 = FEILIU / "goal-2026-08-14"
    for name in sorted(obsolete_goal_14):
        path = feiliu_goal_14 / name
        if path.is_dir():
            roots.append((path.resolve(), "superseded derived review or compile output", False))

    for path in (
        WUBAI / "runtime-records",
        WUBAI / "runtime-reviews",
        WUBAI / "runtime-recovery",
        WUBAI / "format-experiments",
    ):
        if path.is_dir():
            roots.append((path.resolve(), "obsolete runtime evidence or experiment media", False))

    wubai_runtime = WUBAI / "runtime"
    runtime_keep = {
        "wubai-quiet-companion-0.4.0.petsgraph-pet",
        "wubai-quiet-companion-0.3.1.petsgraph-pet",
    }
    if wubai_runtime.is_dir():
        for child in wubai_runtime.iterdir():
            if child.is_dir() and child.name.endswith(".petsgraph-pet") and child.name not in runtime_keep:
                roots.append((child.resolve(), "superseded preview or experimental runtime package", False))

    runtime_builds = WUBAI / "runtime-builds"
    if runtime_builds.is_dir():
        for child in runtime_builds.iterdir():
            if child.is_dir() and child.name.endswith(".petsgraph-pet"):
                roots.append((child.resolve(), "engineering preview or rejected runtime package", False))

    return roots


def approved_recipe_roots() -> list[Path]:
    roots: set[Path] = set()
    for private_root in (WUBAI, FEILIU):
        for recipe in private_root.rglob("approved-recipe.json"):
            roots.add(recipe.parent.resolve())
    roots.add((WUBAI / "runtime/wubai-quiet-companion-0.4.0.petsgraph-pet").resolve())
    roots.add((WUBAI / "runtime/wubai-quiet-companion-0.3.1.petsgraph-pet").resolve())
    roots.add((FEILIU / "goal-2026-08-11/safe-canvas-compile-qa-v3-all-loops").resolve())
    roots.add((FEILIU / "goal-2026-08-11/floor-core-chain-safe-canvas-v1.4-stable-matte").resolve())
    roots.add((FEILIU / "goal-2026-08-11/blanket-matted-safe-reconstruction-seedance2-v22").resolve())
    roots.add((FEILIU / "goal-2026-08-11/blanket-safe-strict-loops-seedance2-v24").resolve())
    roots.add((FEILIU / "goal-2026-08-11/blanket-ultra-still-loops-seedance2-v25").resolve())
    roots.add((FEILIU / "goal-2026-08-11/blanket-supine-pixel-lock-loops-seedance2-v26").resolve())
    roots.add((FEILIU / "goal-2026-08-11/user-rerun-semi-supine-knead-v27").resolve())
    roots.add((FEILIU / "goal-2026-08-14/transition-rebuild-review-v4-all-new-common-transform-final-candidates").resolve())
    roots.add((FEILIU / "goal-2026-08-14/transition-runtime-compile-v7-compact-wide-canvas-all-eight").resolve())
    ordered = sorted((path for path in roots if path.exists()), key=lambda path: len(path.parts))
    minimal: list[Path] = []
    for path in ordered:
        if not any(path == existing or under(path, existing) for existing in minimal):
            minimal.append(path)
    return sorted(minimal)


def protected_snapshot() -> tuple[list[dict[str, object]], str]:
    records: list[dict[str, object]] = []
    digest_lines: list[str] = []
    seen: set[Path] = set()
    for root in approved_recipe_roots():
        count = logical = allocated = 0
        for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
            current = Path(dirpath)
            dirnames[:] = [name for name in dirnames if not (current / name).is_symlink()]
            for filename in filenames:
                path = current / filename
                if path.is_symlink() or path.suffix.lower() not in MEDIA_SUFFIXES:
                    continue
                resolved = path.resolve()
                if resolved in seen:
                    continue
                stat = path.stat()
                digest_lines.append(f"{rel(path)}\t{stat.st_size}\t{stat.st_blocks * 512}")
                seen.add(resolved)
                count += 1
                logical += stat.st_size
                allocated += stat.st_blocks * 512
        records.append({
            "path": rel(root),
            "fileCount": count,
            "logicalBytes": logical,
            "allocatedBytes": allocated,
        })
    return records, sha256_text(sorted(digest_lines))


def collect_candidates() -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    protected = approved_recipe_roots()
    candidate_roots = rejected_job_roots() + superseded_derived_roots()
    deduped: dict[Path, tuple[str, bool]] = {}
    for root, reason, preserve_inputs in sorted(candidate_roots, key=lambda item: len(item[0].parts)):
        if any(root == existing or under(root, existing) for existing in deduped):
            continue
        deduped[root] = (reason, preserve_inputs)

    root_records: list[dict[str, object]] = []
    file_records: list[dict[str, object]] = []
    seen_files: set[Path] = set()
    for root, (reason, preserve_inputs) in sorted(deduped.items(), key=lambda item: rel(item[0])):
        if not (under(root, WUBAI) or under(root, FEILIU)):
            raise RuntimeError(f"candidate root escaped private workspaces: {root}")
        if any(root == item or under(root, item) or under(item, root) for item in protected):
            root_records.append({
                "path": rel(root),
                "reason": reason,
                "status": "skipped-protected-overlap",
                "fileCount": 0,
                "logicalBytes": 0,
                "allocatedBytes": 0,
            })
            continue
        count = logical = allocated = 0
        for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
            current = Path(dirpath)
            dirnames[:] = [name for name in dirnames if not (current / name).is_symlink()]
            relative_parts = current.relative_to(root).parts
            if preserve_inputs and any(part in INPUT_PARTS or part.startswith("input-") for part in relative_parts):
                dirnames[:] = []
                continue
            for filename in filenames:
                path = current / filename
                if path.is_symlink() or path.suffix.lower() not in MEDIA_SUFFIXES:
                    continue
                resolved = path.resolve()
                if resolved in seen_files:
                    continue
                if any(resolved == item or under(resolved, item) for item in protected):
                    continue
                stat = path.stat()
                record = {
                    "path": rel(path),
                    "logicalBytes": stat.st_size,
                    "allocatedBytes": stat.st_blocks * 512,
                    "root": rel(root),
                    "reason": reason,
                }
                file_records.append(record)
                seen_files.add(resolved)
                count += 1
                logical += stat.st_size
                allocated += stat.st_blocks * 512
        root_records.append({
            "path": rel(root),
            "reason": reason,
            "status": "candidate",
            "preserveInputs": preserve_inputs,
            "fileCount": count,
            "logicalBytes": logical,
            "allocatedBytes": allocated,
        })
    return root_records, sorted(file_records, key=lambda item: item["path"])


def build_audit(output: Path) -> dict[str, object]:
    roots, files = collect_candidates()
    protected_roots, protected_digest = protected_snapshot()
    digest_lines = [f"{item['path']}\t{item['logicalBytes']}\t{item['allocatedBytes']}" for item in files]
    payload: dict[str, object] = {
        "schema": 1,
        "status": "audited-not-deleted",
        "scope": [rel(WUBAI), rel(FEILIU)],
        "policy": {
            "deleteOnlyMediaSuffixes": sorted(MEDIA_SUFFIXES),
            "preserve": [
                "approved recipe directories",
                "Wubai 0.4.0 release source package",
                "Wubai 0.3.1 PNG rollback source package",
                "current Feiliu final loop and transition compile evidence",
                "all JSON, prompts, recipes, task IDs, seeds, hashes, and rejection records",
                "input and reference images inside rejected generation jobs",
            ],
        },
        "summary": {
            "candidateRoots": sum(item["status"] == "candidate" for item in roots),
            "skippedProtectedRoots": sum(item["status"] != "candidate" for item in roots),
            "candidateFiles": len(files),
            "logicalBytes": sum(int(item["logicalBytes"]) for item in files),
            "allocatedBytes": sum(int(item["allocatedBytes"]) for item in files),
        },
        "candidateDigest": sha256_text(digest_lines),
        "protectedDigest": protected_digest,
        "protectedRoots": protected_roots,
        "roots": roots,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return payload


def execute(audit_path: Path) -> dict[str, object]:
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    if audit.get("status") != "audited-not-deleted":
        raise SystemExit("Audit manifest is not executable.")
    roots, files = collect_candidates()
    digest_lines = [f"{item['path']}\t{item['logicalBytes']}\t{item['allocatedBytes']}" for item in files]
    current_digest = sha256_text(digest_lines)
    if current_digest != audit.get("candidateDigest"):
        raise SystemExit("Filesystem changed after audit; refusing cleanup.")
    _, protected_before = protected_snapshot()
    if protected_before != audit.get("protectedDigest"):
        raise SystemExit("Protected media changed after audit; refusing cleanup.")
    deleted = logical = allocated = 0
    for item in files:
        path = ROOT / str(item["path"])
        resolved = path.resolve(strict=True)
        if not (under(resolved, WUBAI) or under(resolved, FEILIU)):
            raise RuntimeError(f"refusing path outside private workspaces: {path}")
        if path.is_symlink() or path.suffix.lower() not in MEDIA_SUFFIXES:
            raise RuntimeError(f"refusing unexpected candidate: {path}")
        path.unlink()
        deleted += 1
        logical += int(item["logicalBytes"])
        allocated += int(item["allocatedBytes"])
    _, protected_after = protected_snapshot()
    if protected_after != protected_before:
        raise RuntimeError("Protected media changed during cleanup.")
    receipt = {
        "schema": 1,
        "status": "cleanup-complete",
        "sourceAudit": rel(audit_path),
        "candidateDigest": current_digest,
        "deletedFiles": deleted,
        "logicalBytes": logical,
        "allocatedBytes": allocated,
        "protectedDigestBefore": protected_before,
        "protectedDigestAfter": protected_after,
        "protectedMediaUnchanged": protected_before == protected_after,
        "roots": roots,
    }
    receipt_path = audit_path.with_name(audit_path.stem + ".receipt.json")
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", type=Path)
    parser.add_argument("--execute", type=Path)
    args = parser.parse_args()
    if bool(args.audit) == bool(args.execute):
        raise SystemExit("Choose exactly one of --audit or --execute.")
    if args.audit:
        output = args.audit if args.audit.is_absolute() else ROOT / args.audit
        payload = build_audit(output.resolve())
    else:
        audit_path = args.execute if args.execute.is_absolute() else ROOT / args.execute
        payload = execute(audit_path.resolve(strict=True))
    print(json.dumps(payload["summary"] if "summary" in payload else payload, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
