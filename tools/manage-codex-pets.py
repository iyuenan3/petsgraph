#!/usr/bin/env python3
"""Validate and safely install the repository's Codex pet exports."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import tempfile
from datetime import datetime, timezone
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ASSET_ROOT = REPOSITORY_ROOT / "codex-pets"
MANIFEST_NAME = "manifest.json"
PACKAGE_FILES = {"pet.json", "spritesheet.webp"}


class ValidationError(ValueError):
    """Raised when a Codex pet export violates the repository contract."""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValidationError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValidationError(f"JSON root must be an object: {path}")
    return value


def safe_child(root: Path, name: str) -> Path:
    if not name or name in {".", ".."} or Path(name).name != name:
        raise ValidationError(f"unsafe package directory: {name!r}")
    child = root / name
    if child.is_symlink():
        raise ValidationError(f"package directory must not be a symlink: {child}")
    return child


def webp_info(path: Path) -> tuple[int, int, bool]:
    try:
        data = path.read_bytes()
    except OSError as error:
        raise ValidationError(f"cannot read WebP {path}: {error}") from error
    if len(data) < 20 or data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        raise ValidationError(f"not a RIFF WebP: {path}")

    offset = 12
    width: int | None = None
    height: int | None = None
    has_alpha = False
    while offset + 8 <= len(data):
        fourcc = data[offset : offset + 4]
        size = struct.unpack_from("<I", data, offset + 4)[0]
        start = offset + 8
        end = start + size
        if end > len(data):
            raise ValidationError(f"truncated WebP chunk in {path}")
        chunk = data[start:end]

        if fourcc == b"VP8X" and len(chunk) >= 10:
            has_alpha = has_alpha or bool(chunk[0] & 0x10)
            width = 1 + int.from_bytes(chunk[4:7], "little")
            height = 1 + int.from_bytes(chunk[7:10], "little")
        elif fourcc == b"ALPH":
            has_alpha = True
        elif fourcc == b"VP8 " and len(chunk) >= 10 and chunk[3:6] == b"\x9d\x01\x2a":
            width = struct.unpack_from("<H", chunk, 6)[0] & 0x3FFF
            height = struct.unpack_from("<H", chunk, 8)[0] & 0x3FFF
        elif fourcc == b"VP8L" and len(chunk) >= 5 and chunk[0] == 0x2F:
            bits = int.from_bytes(chunk[1:5], "little")
            width = (bits & 0x3FFF) + 1
            height = ((bits >> 14) & 0x3FFF) + 1
            has_alpha = True

        offset = end + (size & 1)

    if width is None or height is None:
        raise ValidationError(f"cannot determine WebP dimensions: {path}")
    return width, height, has_alpha


def validate_file(path: Path, expected: dict[str, Any]) -> None:
    if path.is_symlink() or not path.is_file():
        raise ValidationError(f"required regular file missing: {path}")
    expected_bytes = expected.get("bytes")
    expected_hash = expected.get("sha256")
    if not isinstance(expected_bytes, int) or expected_bytes < 0:
        raise ValidationError(f"invalid byte count in manifest for {path.name}")
    if not isinstance(expected_hash, str) or len(expected_hash) != 64:
        raise ValidationError(f"invalid SHA-256 in manifest for {path.name}")
    actual_bytes = path.stat().st_size
    if actual_bytes != expected_bytes:
        raise ValidationError(
            f"byte count mismatch for {path}: expected {expected_bytes}, got {actual_bytes}"
        )
    actual_hash = sha256(path)
    if actual_hash != expected_hash:
        raise ValidationError(
            f"SHA-256 mismatch for {path}: expected {expected_hash}, got {actual_hash}"
        )


def validate_repository(root: Path) -> list[dict[str, Any]]:
    root = root.resolve()
    if not root.is_dir():
        raise ValidationError(f"asset root is not a directory: {root}")
    manifest = read_json(root / MANIFEST_NAME)
    if manifest.get("schemaVersion") != 1:
        raise ValidationError("manifest schemaVersion must be 1")

    contract = manifest.get("contract")
    records = manifest.get("pets")
    if not isinstance(contract, dict) or not isinstance(records, list) or not records:
        raise ValidationError("manifest must contain contract and a non-empty pets array")

    expected_dimensions = (contract.get("width"), contract.get("height"))
    if expected_dimensions != (
        contract.get("columns", 0) * contract.get("cellWidth", 0),
        contract.get("rows", 0) * contract.get("cellHeight", 0),
    ):
        raise ValidationError("manifest grid dimensions are inconsistent")

    seen_ids: set[str] = set()
    seen_directories: set[str] = set()
    for record in records:
        if not isinstance(record, dict):
            raise ValidationError("every pets entry must be an object")
        pet_id = record.get("id")
        directory = record.get("directory")
        files = record.get("files")
        if not isinstance(pet_id, str) or not isinstance(directory, str):
            raise ValidationError("every pet needs string id and directory fields")
        if pet_id in seen_ids or directory in seen_directories:
            raise ValidationError(f"duplicate pet id or directory: {pet_id}")
        seen_ids.add(pet_id)
        seen_directories.add(directory)

        package = safe_child(root, directory)
        if not package.is_dir():
            raise ValidationError(f"package directory missing: {package}")
        actual_files = {entry.name for entry in package.iterdir()}
        if actual_files != PACKAGE_FILES:
            raise ValidationError(
                f"unexpected package contents for {pet_id}: {sorted(actual_files)}"
            )
        if not isinstance(files, dict) or set(files) != PACKAGE_FILES:
            raise ValidationError(f"manifest files must be {sorted(PACKAGE_FILES)} for {pet_id}")
        for filename in sorted(PACKAGE_FILES):
            expected = files[filename]
            if not isinstance(expected, dict):
                raise ValidationError(f"invalid file record for {pet_id}/{filename}")
            validate_file(package / filename, expected)

        pet = read_json(package / "pet.json")
        if pet.get("id") != pet_id or pet.get("id") != directory:
            raise ValidationError(f"directory, manifest id, and pet.json id differ for {pet_id}")
        if pet.get("displayName") != record.get("displayName"):
            raise ValidationError(f"displayName mismatch for {pet_id}")
        if pet.get("spriteVersionNumber") != contract.get("spriteVersionNumber"):
            raise ValidationError(f"sprite version mismatch for {pet_id}")
        if pet.get("spritesheetPath") != "spritesheet.webp":
            raise ValidationError(f"unexpected spritesheetPath for {pet_id}")

        width, height, has_alpha = webp_info(package / "spritesheet.webp")
        if (width, height) != expected_dimensions:
            raise ValidationError(
                f"spritesheet dimensions mismatch for {pet_id}: {width}x{height}"
            )
        if not has_alpha:
            raise ValidationError(f"spritesheet has no declared alpha channel: {pet_id}")

    top_level_directories = {
        entry.name for entry in root.iterdir() if entry.is_dir() and not entry.is_symlink()
    }
    if top_level_directories != seen_directories:
        raise ValidationError(
            "manifest/package directory mismatch: "
            f"expected {sorted(seen_directories)}, got {sorted(top_level_directories)}"
        )
    expected_entries = {MANIFEST_NAME, "README.md", *seen_directories}
    actual_entries = {entry.name for entry in root.iterdir()}
    if actual_entries != expected_entries:
        raise ValidationError(
            "unexpected asset root contents: "
            f"expected {sorted(expected_entries)}, got {sorted(actual_entries)}"
        )
    for entry in root.iterdir():
        if entry.is_symlink():
            raise ValidationError(f"asset root entries must not be symlinks: {entry}")
    return records


def package_matches(source: Path, target: Path) -> bool:
    if target.is_symlink() or not target.is_dir():
        return False
    try:
        if {entry.name for entry in target.iterdir()} != PACKAGE_FILES:
            return False
        return all(
            (target / filename).is_file()
            and not (target / filename).is_symlink()
            and sha256(source / filename) == sha256(target / filename)
            for filename in PACKAGE_FILES
        )
    except OSError:
        return False


def install_packages(
    root: Path,
    records: list[dict[str, Any]],
    selected_ids: list[str],
    codex_home: Path,
    force: bool,
) -> None:
    by_id = {str(record["id"]): record for record in records}
    selected = selected_ids or list(by_id)
    if len(selected) != len(set(selected)):
        raise ValidationError("pet ids must not be repeated")
    unknown = sorted(set(selected) - set(by_id))
    if unknown:
        raise ValidationError(f"unknown pet id: {', '.join(unknown)}")

    codex_home = codex_home.expanduser().resolve()
    if codex_home == Path(codex_home.anchor):
        raise ValidationError("Codex home must not be a filesystem root")
    pets_root = codex_home / "pets"
    if pets_root.is_symlink():
        raise ValidationError(f"Codex pets directory must not be a symlink: {pets_root}")
    plans: list[tuple[str, Path, Path, str]] = []
    for pet_id in selected:
        record = by_id[pet_id]
        source = safe_child(root.resolve(), str(record["directory"]))
        target = pets_root / pet_id
        if target.exists() or target.is_symlink():
            if package_matches(source, target):
                plans.append((pet_id, source, target, "unchanged"))
            elif force:
                plans.append((pet_id, source, target, "replace"))
            else:
                raise ValidationError(
                    f"refusing to overwrite different installed package {target}; use --force"
                )
        else:
            plans.append((pet_id, source, target, "install"))

    pets_root.mkdir(parents=True, exist_ok=True)
    backup_root: Path | None = None
    for pet_id, source, target, action in plans:
        if action == "unchanged":
            print(f"unchanged {pet_id}: {target}")
            continue

        staging = Path(tempfile.mkdtemp(prefix=f".{pet_id}.install-", dir=pets_root))
        try:
            for filename in PACKAGE_FILES:
                shutil.copy2(source / filename, staging / filename)

            backup: Path | None = None
            if action == "replace":
                if backup_root is None:
                    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
                    backup_root = codex_home / "pets-backups" / stamp
                    backup_root.mkdir(parents=True, exist_ok=False)
                backup = backup_root / pet_id
                target.rename(backup)

            try:
                staging.rename(target)
            except Exception:
                if backup is not None and not target.exists():
                    backup.rename(target)
                raise
            verb = "replaced" if action == "replace" else "installed"
            print(f"{verb} {pet_id}: {target}")
        finally:
            if staging.exists():
                shutil.rmtree(staging)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate or safely install the repository's Codex pet exports."
    )
    parser.add_argument(
        "--root", type=Path, default=DEFAULT_ASSET_ROOT, help="Codex pet asset root"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate", help="validate manifest, hashes, and v2 atlas geometry")

    install = subparsers.add_parser("install", help="install validated packages into Codex")
    install.add_argument("pets", nargs="*", help="pet ids; defaults to every manifest entry")
    install.add_argument(
        "--codex-home",
        type=Path,
        default=Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")),
        help="Codex data directory",
    )
    install.add_argument(
        "--force",
        action="store_true",
        help="replace differing packages after moving originals to pets-backups",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        records = validate_repository(args.root)
        if args.command == "validate":
            for record in records:
                print(f"valid {record['id']}: {record['displayName']}")
            print(f"validated {len(records)} Codex pet packages")
        else:
            install_packages(args.root, records, args.pets, args.codex_home, args.force)
        return 0
    except ValidationError as error:
        print(f"error: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
