#!/usr/bin/env python3
"""Delete unreferenced private media after an immutable audit.

The cleanup preserves final compiled assets, approved material, input/reference
photos, release packages, and all non-media production records. It only unlinks
explicit media paths listed by an audit from the same filesystem snapshot.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
PRIVATE_ROOTS = [ROOT / "workspaces/wubai-private", ROOT / "workspaces/feiliu-private"]
AUDIT_ROOT = ROOT / "workspaces/cleanup-audits"
FINAL_FEILIU = ROOT / "workspaces/feiliu-private/goal-2026-08-15/feiliu-final-graph-v4"
MEDIA_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".mp4", ".mov", ".mkv", ".avi", ".webm",
    ".gif", ".webp", ".raw", ".rgba", ".bin", ".heic", ".tiff", ".tif",
}
INPUT_NAMES = {
    "input", "inputs", "input-shared", "references", "foundation",
    "sleep-foundation", "input-safe", "input-aligned", "source-photos",
}

# These manifests are the authoritative source lineage for the currently frozen
# Feiliu graph.  The compiled v4 graph is self-contained, but its node records
# intentionally point only at compiled frame directories.  Keep the approved
# source videos and QA media referenced by these manifests so cleanup never
# turns the compiled package into the only surviving copy of an accepted node.
AUTHORITATIVE_FEILIU_RECORDS = (
    "workspaces/feiliu-private/goal-2026-08-11/safe-canvas-compile-qa-v3-all-loops/manifest.json",
    "workspaces/feiliu-private/goal-2026-08-11/floor-core-chain-safe-canvas-v1.4-stable-matte/manifest.json",
    "workspaces/feiliu-private/goal-2026-08-14/new-supine-right-runtime-chain-v6-unified-clean-matte/manifest.json",
    "workspaces/feiliu-private/actions/cat-bed-sit-front-to-curled-to-sit-front/minimal-chain-review-v8/manifest.json",
    "workspaces/feiliu-private/actions/cat-bed-sit-front-to-curled-to-sit-front/transition-review-v2-tail-contained/manifest.json",
    "workspaces/feiliu-private/actions/cat-bed-sit-front-to-curled-to-sit-front/transition-review-side-stretched-v1/manifest.json",
    "workspaces/feiliu-private/actions/cat-bed-sit-front-to-curled-to-sit-front/transition-review-open-belly-final-v3/manifest.json",
    "workspaces/feiliu-private/actions/floor-prone-to-cat-bed-curled-v1/qa-v4/manifest.json",
    "workspaces/feiliu-private/actions/cat-bed-curled-to-floor-prone-v1/qa-v1/manifest.json",
)


def under(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def sha256_lines(lines: Iterable[str]) -> str:
    digest = hashlib.sha256()
    for line in lines:
        digest.update(line.encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def walk_strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from walk_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_strings(child)


def is_approved_record(path: Path) -> bool:
    if path.name == "approved-recipe.json":
        return True
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return False
    tokens: list[str] = []
    for key in ("status", "decision", "humanStatus", "approvalStatus"):
        value = data.get(key) if isinstance(data, dict) else None
        if isinstance(value, str):
            tokens.append(value.lower())
    return any(token == "approved" or "human-approved" in token or "human-matte-approved" in token for token in tokens)


def resolve_reference(value: str, record: Path) -> Path | None:
    if not value or value.startswith(("http://", "https://", "tos://")):
        return None
    candidates = [ROOT / value, record.parent / value]
    for candidate in candidates:
        try:
            resolved = candidate.resolve(strict=True)
        except OSError:
            continue
        if any(under(resolved, root) for root in PRIVATE_ROOTS):
            return resolved
    return None


def protection_set() -> tuple[set[Path], set[Path], list[Path]]:
    exact_files: set[Path] = set()
    exact_dirs: set[Path] = set()
    records: list[Path] = []

    exact_dirs.add(FINAL_FEILIU.resolve(strict=True))
    for path in (
        ROOT / "workspaces/wubai-private/runtime/wubai-quiet-companion-0.4.0.petsgraph-pet",
        ROOT / "workspaces/wubai-private/runtime/wubai-quiet-companion-0.3.1.petsgraph-pet",
        ROOT / "workspaces/wubai-private/release-dist",
    ):
        if path.exists():
            exact_dirs.add(path.resolve())

    for private_root in PRIVATE_ROOTS:
        for directory in private_root.rglob("*"):
            if directory.is_dir() and (
                directory.name in INPUT_NAMES
                or directory.name.startswith("input-")
                or directory.name.endswith("-inputs")
            ):
                exact_dirs.add(directory.resolve())

        for recipe in private_root.rglob("approved-recipe.json"):
            records.append(recipe)
            exact_dirs.add(recipe.parent.resolve())

        registry = private_root / "approved-assets.json"
        if registry.is_file():
            records.append(registry)

        for name in ("human-review.json", "human-approval.json", "approval.json"):
            for review in private_root.rglob(name):
                if is_approved_record(review):
                    records.append(review)
                    exact_dirs.add(review.parent.resolve())

    final_manifest = FINAL_FEILIU / "manifest.json"
    records.append(final_manifest)
    for relative in AUTHORITATIVE_FEILIU_RECORDS:
        record = ROOT / relative
        if not record.is_file():
            raise FileNotFoundError(f"Missing authoritative protection record: {record}")
        records.append(record)

    for record in records:
        try:
            data = json.loads(record.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            continue
        for value in walk_strings(data):
            resolved = resolve_reference(value, record)
            if resolved is None:
                continue
            if resolved.is_dir():
                exact_dirs.add(resolved)
            elif resolved.suffix.lower() in MEDIA_SUFFIXES:
                exact_files.add(resolved)

    minimal_dirs: list[Path] = []
    for directory in sorted(exact_dirs, key=lambda path: len(path.parts)):
        if not any(directory == parent or under(directory, parent) for parent in minimal_dirs):
            minimal_dirs.append(directory)
    exact_files = {
        path for path in exact_files
        if not any(path == directory or under(path, directory) for directory in minimal_dirs)
    }
    return exact_files, set(minimal_dirs), sorted(set(records))


def is_protected(path: Path, files: set[Path], directories: set[Path]) -> bool:
    resolved = path.resolve()
    return resolved in files or any(parent in directories for parent in (resolved, *resolved.parents))


def validate_snapshot(
    candidates: list[dict[str, Any]],
    protected_files: set[Path],
    protected_dirs: set[Path],
    records: list[Path],
) -> dict[str, Any]:
    candidate_paths = {(ROOT / item["path"]).resolve() for item in candidates}
    if len(candidate_paths) != len(candidates):
        raise RuntimeError("Cleanup candidates are not unique")
    if candidate_paths & protected_files:
        raise RuntimeError("Cleanup candidates intersect protected files")
    for path in candidate_paths:
        if any(parent in protected_dirs for parent in (path, *path.parents)):
            raise RuntimeError(f"Cleanup candidate is below a protected directory: {path}")

    final_manifest = FINAL_FEILIU / "manifest.json"
    graph = json.loads(final_manifest.read_text(encoding="utf-8"))
    nodes = graph.get("nodes", [])
    edges = graph.get("edges", [])
    if len(nodes) != 12 or len(edges) != 22:
        raise RuntimeError(f"Unexpected frozen graph size: {len(nodes)} nodes, {len(edges)} edges")

    compiled_sequences = 0
    compiled_frames = 0
    for item in [*nodes, *edges]:
        directory = ROOT / item["compiledFrames"]
        if not directory.is_dir():
            raise FileNotFoundError(f"Missing frozen frame directory: {directory}")
        actual = len(list(directory.glob("frame-*.png")))
        expected = item.get("frameCount")
        if actual != expected:
            raise RuntimeError(f"Frozen frame count mismatch for {item['id']}: {actual} != {expected}")
        compiled_sequences += 1
        compiled_frames += actual

    source_videos = 0
    for edge in edges:
        source = edge.get("source")
        if not isinstance(source, dict) or not source.get("path"):
            continue
        path = (ROOT / source["path"]).resolve(strict=True)
        if path in candidate_paths:
            raise RuntimeError(f"Frozen edge source is marked for deletion: {path}")
        expected_sha = source.get("sha256")
        if expected_sha and sha256(path) != expected_sha:
            raise RuntimeError(f"Frozen edge source hash mismatch: {path}")
        source_videos += 1

    referenced_media = 0
    for record in records:
        data = json.loads(record.read_text(encoding="utf-8"))
        for value in walk_strings(data):
            resolved = resolve_reference(value, record)
            if resolved is None or resolved.is_dir() or resolved.suffix.lower() not in MEDIA_SUFFIXES:
                continue
            if resolved in candidate_paths:
                raise RuntimeError(f"Protected record media is marked for deletion: {resolved}")
            referenced_media += 1

    return {
        "passed": True,
        "frozenGraphNodes": len(nodes),
        "frozenGraphEdges": len(edges),
        "frozenCompiledSequences": compiled_sequences,
        "frozenCompiledFrames": compiled_frames,
        "frozenEdgeSourceVideosHashVerified": source_videos,
        "authoritativeRecordsRead": len(records),
        "resolvedProtectedMediaReferences": referenced_media,
        "candidateProtectedIntersection": 0,
    }


def snapshot() -> dict[str, Any]:
    protected_files, protected_dirs, records = protection_set()
    candidates: list[dict[str, Any]] = []
    protected_media: list[str] = []
    by_top: dict[str, dict[str, int]] = defaultdict(lambda: {"files": 0, "logicalBytes": 0, "allocatedBytes": 0})

    for private_root in PRIVATE_ROOTS:
        for dirpath, dirnames, filenames in os.walk(private_root, followlinks=False):
            current = Path(dirpath)
            dirnames[:] = [name for name in dirnames if not (current / name).is_symlink()]
            for filename in filenames:
                path = current / filename
                if path.is_symlink() or path.suffix.lower() not in MEDIA_SUFFIXES:
                    continue
                resolved = path.resolve()
                if is_protected(path, protected_files, protected_dirs):
                    stat = path.stat()
                    protected_media.append(f"{rel(path)}\t{stat.st_size}\t{stat.st_blocks * 512}")
                    continue
                stat = path.stat()
                relative = path.relative_to(private_root)
                top = "/".join(relative.parts[:2]) if len(relative.parts) > 1 else relative.as_posix()
                key = f"{private_root.name}/{top}"
                record = {
                    "path": rel(path),
                    "logicalBytes": stat.st_size,
                    "allocatedBytes": stat.st_blocks * 512,
                    "mtimeNs": stat.st_mtime_ns,
                }
                candidates.append(record)
                by_top[key]["files"] += 1
                by_top[key]["logicalBytes"] += stat.st_size
                by_top[key]["allocatedBytes"] += stat.st_blocks * 512

    candidates.sort(key=lambda item: item["path"])
    validation = validate_snapshot(candidates, protected_files, protected_dirs, records)
    lines = [f"{item['path']}\t{item['logicalBytes']}\t{item['allocatedBytes']}\t{item['mtimeNs']}" for item in candidates]
    return {
        "candidates": candidates,
        "candidateDigest": sha256_lines(lines),
        "protectedDigest": sha256_lines(sorted(protected_media)),
        "protectedFileCount": len(protected_media),
        "protectionRecords": [rel(path) for path in records],
        "protectedDirectories": [rel(path) for path in sorted(protected_dirs)],
        "byTopDirectory": dict(sorted(by_top.items())),
        "validation": validation,
    }


def audit(output: Path) -> dict[str, Any]:
    state = snapshot()
    candidates = state.pop("candidates")
    payload = {
        "schema": 1,
        "status": "audited-not-deleted",
        "scope": [rel(root) for root in PRIVATE_ROOTS],
        "policy": {
            "deleteOnlyMediaSuffixes": sorted(MEDIA_SUFFIXES),
            "preserveAllNonMediaRecords": True,
            "preserveFinalFeiliuGraph": rel(FINAL_FEILIU),
            "preserveApprovedRecipesAndReviews": True,
            "preserveInputsReferencesFoundations": True,
            "preserveWubaiReleaseAndRollbackPackages": True,
        },
        "summary": {
            "candidateFiles": len(candidates),
            "logicalBytes": sum(item["logicalBytes"] for item in candidates),
            "allocatedBytes": sum(item["allocatedBytes"] for item in candidates),
            "protectedMediaFiles": state["protectedFileCount"],
        },
        **state,
        "files": candidates,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return payload


def execute(audit_path: Path) -> dict[str, Any]:
    payload = json.loads(audit_path.read_text(encoding="utf-8"))
    if payload.get("status") != "audited-not-deleted":
        raise SystemExit("Audit manifest is not executable")
    current = snapshot()
    if current["candidateDigest"] != payload.get("candidateDigest"):
        raise SystemExit("Candidate filesystem changed after audit; refusing cleanup")
    if current["protectedDigest"] != payload.get("protectedDigest"):
        raise SystemExit("Protected filesystem changed after audit; refusing cleanup")

    final_manifest = FINAL_FEILIU / "manifest.json"
    final_video = FINAL_FEILIU / "feiliu-final-10-sleep-pose-22-edge-complete-tour-standard.mp4"
    protected_before = {rel(path): sha256(path) for path in (final_manifest, final_video)}
    deleted = logical = allocated = 0
    for item in payload["files"]:
        path = ROOT / item["path"]
        resolved = path.resolve(strict=True)
        if not any(under(resolved, root) for root in PRIVATE_ROOTS):
            raise RuntimeError(f"Path escaped private roots: {path}")
        if path.is_symlink() or path.suffix.lower() not in MEDIA_SUFFIXES:
            raise RuntimeError(f"Unexpected cleanup candidate: {path}")
        stat = path.stat()
        if stat.st_size != item["logicalBytes"] or stat.st_mtime_ns != item["mtimeNs"]:
            raise RuntimeError(f"Candidate changed during cleanup: {path}")
        path.unlink()
        deleted += 1
        logical += item["logicalBytes"]
        allocated += item["allocatedBytes"]

    protected_after = {rel(path): sha256(path) for path in (final_manifest, final_video)}
    if protected_after != protected_before:
        raise RuntimeError("Final Feiliu manifest or review video changed during cleanup")
    receipt = {
        "schema": 1,
        "status": "cleanup-complete",
        "sourceAudit": rel(audit_path),
        "candidateDigest": current["candidateDigest"],
        "deletedFiles": deleted,
        "logicalBytes": logical,
        "allocatedBytes": allocated,
        "finalEvidenceBefore": protected_before,
        "finalEvidenceAfter": protected_after,
        "finalEvidenceUnchanged": protected_before == protected_after,
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
        raise SystemExit("Choose exactly one of --audit or --execute")
    if args.audit:
        output = args.audit if args.audit.is_absolute() else ROOT / args.audit
        result = audit(output.resolve())
        print(json.dumps({"summary": result["summary"], "byTopDirectory": result["byTopDirectory"]}, ensure_ascii=False, indent=2))
    else:
        source = args.execute if args.execute.is_absolute() else ROOT / args.execute
        print(json.dumps(execute(source.resolve(strict=True)), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
