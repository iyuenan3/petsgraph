#!/usr/bin/env python3
"""Audit and remove superseded Feiliu goal-2026-08-16 media.

The cleanup is intentionally narrow. It protects every selected directory and
hash recorded by the human-approved selective fine-matte graph tour, follows
its local JSON lineage for additional referenced media, preserves every
non-media production record, and deletes only media listed by a matching audit.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
GOAL = ROOT / "workspaces/feiliu-private/goal-2026-08-16"
FINAL = GOAL / "feiliu-selective-fine-matte-graph-tour-v2/manifest.json"
AUDIT_ROOT = ROOT / "workspaces/cleanup-audits"
MEDIA_SUFFIXES = {
    ".avi",
    ".bin",
    ".gif",
    ".heic",
    ".jpeg",
    ".jpg",
    ".mkv",
    ".mov",
    ".mp4",
    ".png",
    ".raw",
    ".rgba",
    ".tif",
    ".tiff",
    ".webm",
    ".webp",
}


def under(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def digest_lines(lines: Iterable[str]) -> str:
    digest = hashlib.sha256()
    for line in lines:
        digest.update(line.encode("utf-8"))
        digest.update(b"\n")
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


def resolve_local(value: str, record: Path) -> Path | None:
    if not value or value.startswith(("http://", "https://", "tos://")):
        return None
    for candidate in (ROOT / value, record.parent / value):
        try:
            resolved = candidate.resolve(strict=True)
        except OSError:
            continue
        if under(resolved, GOAL):
            return resolved
    return None


def load_final() -> dict[str, Any]:
    payload = json.loads(FINAL.read_text(encoding="utf-8"))
    if payload.get("status") != "human-approved-selective-fine-matte-graph-tour":
        raise RuntimeError("final Feiliu graph tour is not the expected human-approved version")
    scope = payload.get("scope", {})
    records = payload.get("uniqueRecords", [])
    if (
        scope.get("nodeCount") != 11
        or scope.get("directedEdgeCount") != 20
        or scope.get("uniqueClipCount") != 31
        or len(records) != 31
    ):
        raise RuntimeError("unexpected final Feiliu graph scope")
    if scope.get("includesLoaf") is not False or scope.get("keepsSemiSupineRoute") is not True:
        raise RuntimeError("unexpected final Feiliu graph topology flags")
    return payload


def selected_snapshot(payload: dict[str, Any]) -> tuple[list[dict[str, str]], str]:
    snapshot: list[dict[str, str]] = []
    lines: list[str] = []
    clip_ids: set[str] = set()
    for record in payload["uniqueRecords"]:
        clip_id = record["clipId"]
        if clip_id in clip_ids:
            raise RuntimeError(f"duplicate selected clip: {clip_id}")
        clip_ids.add(clip_id)
        for path_key, hash_key in (
            ("manifest", "manifestSha256"),
            ("segment", "segmentSha256"),
            ("firstRgba", "firstRgbaSha256"),
            ("lastRgba", "lastRgbaSha256"),
        ):
            path = (ROOT / record[path_key]).resolve(strict=True)
            if not under(path, GOAL):
                raise RuntimeError(f"selected file escaped goal directory: {path}")
            actual = sha256(path)
            expected = record[hash_key]
            if actual != expected:
                raise RuntimeError(f"selected hash mismatch: {path}")
            snapshot.append({"path": rel(path), "sha256": actual})
            lines.append(f"{rel(path)}\t{actual}")
    return snapshot, digest_lines(sorted(lines))


def protection_set(payload: dict[str, Any]) -> tuple[set[Path], set[Path], list[Path]]:
    protected_dirs: set[Path] = {FINAL.parent.resolve()}
    protected_files: set[Path] = set()
    json_queue: list[Path] = [FINAL.resolve()]
    seen_json: set[Path] = set()

    for record in payload["uniqueRecords"]:
        manifest = (ROOT / record["manifest"]).resolve(strict=True)
        protected_dirs.add(manifest.parent)
        json_queue.append(manifest)
        clip_manifest = manifest.parent / "clips" / record["clipId"] / "clip-manifest.json"
        segment_manifest = (
            manifest.parent
            / "aligned-segments"
            / record["clipId"]
            / "segment-manifest.json"
        )
        for path in (clip_manifest, segment_manifest):
            if path.is_file():
                json_queue.append(path.resolve())

    input_lock = payload.get("inputLock", {}).get("path")
    if input_lock:
        path = (ROOT / input_lock).resolve(strict=True)
        protected_dirs.add(path.parent)
        json_queue.append(path)

    while json_queue:
        record = json_queue.pop()
        if record in seen_json or not record.is_file() or record.suffix.lower() != ".json":
            continue
        seen_json.add(record)
        try:
            data = json.loads(record.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            continue
        for value in walk_strings(data):
            resolved = resolve_local(value, record)
            if resolved is None:
                continue
            if resolved.is_dir():
                protected_dirs.add(resolved)
            elif resolved.suffix.lower() in MEDIA_SUFFIXES:
                protected_files.add(resolved)
            elif resolved.suffix.lower() == ".json":
                json_queue.append(resolved)

    minimal_dirs: list[Path] = []
    for directory in sorted(protected_dirs, key=lambda item: len(item.parts)):
        if not any(directory == parent or under(directory, parent) for parent in minimal_dirs):
            minimal_dirs.append(directory)
    protected_files = {
        path
        for path in protected_files
        if not any(path == directory or under(path, directory) for directory in minimal_dirs)
    }
    return protected_files, set(minimal_dirs), sorted(seen_json)


def is_protected(path: Path, files: set[Path], directories: set[Path]) -> bool:
    resolved = path.resolve()
    return resolved in files or any(
        resolved == directory or under(resolved, directory) for directory in directories
    )


def collect_candidates(
    protected_files: set[Path], protected_dirs: set[Path]
) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    for dirpath, dirnames, filenames in os.walk(GOAL, followlinks=False):
        current = Path(dirpath)
        dirnames[:] = [name for name in dirnames if not (current / name).is_symlink()]
        for filename in filenames:
            path = current / filename
            if path.is_symlink() or path.suffix.lower() not in MEDIA_SUFFIXES:
                continue
            if is_protected(path, protected_files, protected_dirs):
                continue
            stat = path.stat()
            candidates.append(
                {
                    "path": rel(path),
                    "logicalBytes": stat.st_size,
                    "allocatedBytes": stat.st_blocks * 512,
                    "mtimeNs": stat.st_mtime_ns,
                }
            )
    return sorted(candidates, key=lambda item: item["path"])


def candidate_digest(candidates: list[dict[str, Any]]) -> str:
    return digest_lines(
        f"{item['path']}\t{item['logicalBytes']}\t{item['allocatedBytes']}\t{item['mtimeNs']}"
        for item in candidates
    )


def build_audit(output: Path) -> dict[str, Any]:
    payload = load_final()
    selected, selected_digest = selected_snapshot(payload)
    protected_files, protected_dirs, lineage_records = protection_set(payload)
    candidates = collect_candidates(protected_files, protected_dirs)
    result = {
        "schema": 1,
        "status": "audited-not-deleted",
        "scope": rel(GOAL),
        "authority": rel(FINAL),
        "policy": {
            "deleteOnlyMediaSuffixes": sorted(MEDIA_SUFFIXES),
            "preserveAllNonMediaRecords": True,
            "preserveSelectedClipDirectories": True,
            "preserveReferencedLocalLineageMedia": True,
        },
        "selectedSnapshot": selected,
        "selectedDigest": selected_digest,
        "protectedDirectories": [rel(path) for path in sorted(protected_dirs)],
        "protectedFiles": [rel(path) for path in sorted(protected_files)],
        "lineageRecordsRead": [rel(path) for path in lineage_records],
        "summary": {
            "selectedClips": len(payload["uniqueRecords"]),
            "candidateFiles": len(candidates),
            "logicalBytes": sum(item["logicalBytes"] for item in candidates),
            "allocatedBytes": sum(item["allocatedBytes"] for item in candidates),
        },
        "candidateDigest": candidate_digest(candidates),
        "files": candidates,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def execute(audit_path: Path) -> dict[str, Any]:
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    if audit.get("status") != "audited-not-deleted" or audit.get("authority") != rel(FINAL):
        raise SystemExit("audit manifest is not executable")
    payload = load_final()
    _, selected_digest_before = selected_snapshot(payload)
    if selected_digest_before != audit.get("selectedDigest"):
        raise SystemExit("selected media changed after audit; refusing cleanup")
    protected_files, protected_dirs, _ = protection_set(payload)
    candidates = collect_candidates(protected_files, protected_dirs)
    if candidate_digest(candidates) != audit.get("candidateDigest"):
        raise SystemExit("candidate filesystem changed after audit; refusing cleanup")
    if candidates != audit.get("files"):
        raise SystemExit("candidate list changed after audit; refusing cleanup")

    deleted = 0
    logical = 0
    allocated = 0
    for item in candidates:
        path = ROOT / item["path"]
        resolved = path.resolve(strict=True)
        if not under(resolved, GOAL):
            raise RuntimeError(f"cleanup path escaped goal directory: {path}")
        if path.is_symlink() or path.suffix.lower() not in MEDIA_SUFFIXES:
            raise RuntimeError(f"unexpected cleanup candidate: {path}")
        stat = path.stat()
        if stat.st_size != item["logicalBytes"] or stat.st_mtime_ns != item["mtimeNs"]:
            raise RuntimeError(f"cleanup candidate changed: {path}")
        path.unlink()
        deleted += 1
        logical += item["logicalBytes"]
        allocated += item["allocatedBytes"]

    _, selected_digest_after = selected_snapshot(payload)
    if selected_digest_after != selected_digest_before:
        raise RuntimeError("selected media changed during cleanup")
    receipt = {
        "schema": 1,
        "status": "cleanup-complete",
        "sourceAudit": rel(audit_path),
        "deletedFiles": deleted,
        "logicalBytes": logical,
        "allocatedBytes": allocated,
        "selectedDigestBefore": selected_digest_before,
        "selectedDigestAfter": selected_digest_after,
        "selectedMediaUnchanged": selected_digest_before == selected_digest_after,
    }
    receipt_path = audit_path.with_name(audit_path.stem + ".receipt.json")
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return receipt


def verify_interrupted_execute(audit_path: Path) -> dict[str, Any]:
    """Verify a cleanup that finished unlinking before its receipt was written."""
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    if audit.get("status") != "audited-not-deleted" or audit.get("authority") != rel(FINAL):
        raise SystemExit("audit manifest is not verifiable")
    payload = load_final()
    selected, selected_digest = selected_snapshot(payload)
    if selected_digest != audit.get("selectedDigest"):
        raise SystemExit("selected media changed; interrupted cleanup cannot be certified")
    missing_selected = [item["path"] for item in selected if not (ROOT / item["path"]).is_file()]
    if missing_selected:
        raise RuntimeError(f"selected files are missing: {missing_selected[:3]}")
    remaining_audit_candidates = [
        item["path"] for item in audit.get("files", []) if (ROOT / item["path"]).exists()
    ]
    if remaining_audit_candidates:
        raise RuntimeError(
            "interrupted cleanup left audited candidates behind: "
            + ", ".join(remaining_audit_candidates[:3])
        )
    protected_files, protected_dirs, _ = protection_set(payload)
    unexpected_candidates = collect_candidates(protected_files, protected_dirs)
    if unexpected_candidates:
        raise RuntimeError(
            f"unexpected unprotected media remains after cleanup: {len(unexpected_candidates)} files"
        )
    summary = audit["summary"]
    receipt = {
        "schema": 1,
        "status": "cleanup-complete-verified-after-exec-timeout",
        "sourceAudit": rel(audit_path),
        "deletedFilesVerifiedAbsent": summary["candidateFiles"],
        "logicalBytes": summary["logicalBytes"],
        "allocatedBytes": summary["allocatedBytes"],
        "selectedFilesHashVerified": len(selected),
        "selectedDigest": selected_digest,
        "selectedMediaUnchanged": True,
        "remainingAuditedCandidates": 0,
        "remainingUnexpectedCandidates": 0,
    }
    receipt_path = audit_path.with_name(audit_path.stem + ".verified-receipt.json")
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", type=Path)
    parser.add_argument("--execute", type=Path)
    parser.add_argument("--verify-interrupted", type=Path)
    args = parser.parse_args()
    if sum(bool(value) for value in (args.audit, args.execute, args.verify_interrupted)) != 1:
        raise SystemExit("choose exactly one of --audit, --execute, or --verify-interrupted")
    if args.audit:
        output = args.audit if args.audit.is_absolute() else ROOT / args.audit
        result = build_audit(output.resolve())
        print(json.dumps(result["summary"], ensure_ascii=False, indent=2))
    elif args.execute:
        source = args.execute if args.execute.is_absolute() else ROOT / args.execute
        print(json.dumps(execute(source.resolve(strict=True)), ensure_ascii=False, indent=2))
    else:
        source = (
            args.verify_interrupted
            if args.verify_interrupted.is_absolute()
            else ROOT / args.verify_interrupted
        )
        print(
            json.dumps(
                verify_interrupted_execute(source.resolve(strict=True)),
                ensure_ascii=False,
                indent=2,
            )
        )


if __name__ == "__main__":
    main()
