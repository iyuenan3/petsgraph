from __future__ import annotations

import hashlib
import json
import math
import re
import stat
import unicodedata
import zipfile
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping


FORMAT_VERSION = "1.0.0"
BASELINE_CAPABILITY = "cropped-rgba-clips"
SUPPORTED_REQUIRED_CAPABILITIES = frozenset({BASELINE_CAPABILITY})
PACKAGE_ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
NODE_ID_RE = re.compile(r"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
CLIP_ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SEMVER_RE = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"
)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ALLOWED_COMPRESSION = frozenset({zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED})
PROHIBITED_SUFFIXES = frozenset(
    {
        ".app",
        ".bat",
        ".class",
        ".cmd",
        ".com",
        ".dll",
        ".dylib",
        ".exe",
        ".jar",
        ".js",
        ".msi",
        ".pkg",
        ".ps1",
        ".py",
        ".sh",
        ".so",
        ".swift",
        ".vbs",
    }
)
WINDOWS_RESERVED_NAMES = frozenset(
    {"con", "prn", "aux", "nul", "clock$"}
    | {f"com{number}" for number in range(1, 10)}
    | {f"lpt{number}" for number in range(1, 10)}
)
REQUIRED_ROOT_FILES = frozenset(
    {"manifest.json", "graph.json", "behavior.json", "integrity.json"}
)


@dataclass(frozen=True)
class PetPackLimits:
    max_entries: int = 100_000
    max_archive_bytes: int = 64 * 1024**3
    max_uncompressed_bytes: int = 64 * 1024**3
    max_single_entry_bytes: int = 32 * 1024**3
    max_json_bytes: int = 16 * 1024**2
    max_compression_ratio: float = 200.0


@dataclass(frozen=True)
class PetPackValidationReport:
    path: str
    package_id: str
    pet_id: str
    species: str
    content_version: str
    format_version: str
    archive_bytes: int
    uncompressed_bytes: int
    entry_count: int
    clip_count: int
    node_count: int
    edge_count: int
    representation_kinds: tuple[str, ...]
    signed: bool = False

    def as_dict(self) -> dict[str, Any]:
        result = asdict(self)
        result["representation_kinds"] = list(self.representation_kinds)
        result["valid"] = True
        return result


class PetPackValidationError(Exception):
    def __init__(self, code: str, detail: str):
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}")

    def as_dict(self) -> dict[str, Any]:
        return {"valid": False, "code": self.code, "detail": self.detail}


class _DuplicateJSONKey(ValueError):
    pass


def _fail(code: str, detail: str) -> None:
    raise PetPackValidationError(code, detail)


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _object(value: Any, where: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        _fail("invalid_json_shape", f"{where} must be an object")
    return value


def _array(value: Any, where: str) -> list[Any]:
    if not isinstance(value, list):
        _fail("invalid_json_shape", f"{where} must be an array")
    return value


def _keys(
    value: Mapping[str, Any],
    where: str,
    required: Iterable[str],
    optional: Iterable[str] = (),
) -> None:
    required_set = set(required)
    allowed = required_set | set(optional)
    missing = sorted(required_set - value.keys())
    unknown = sorted(value.keys() - allowed)
    if missing:
        _fail("missing_field", f"{where} is missing {', '.join(missing)}")
    if unknown:
        _fail("unknown_field", f"{where} contains {', '.join(unknown)}")


def _string(value: Any, where: str, *, maximum: int = 4096) -> str:
    if not isinstance(value, str) or not value or len(value) > maximum:
        _fail("invalid_value", f"{where} must be a non-empty string")
    if unicodedata.normalize("NFC", value) != value:
        _fail("unicode_not_nfc", f"{where} must use NFC Unicode")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        _fail("invalid_value", f"{where} contains a control character")
    return value


def _identifier(value: Any, where: str, pattern: re.Pattern[str], maximum: int) -> str:
    result = _string(value, where, maximum=maximum)
    if pattern.fullmatch(result) is None:
        _fail("invalid_identifier", f"{where} has an invalid identifier")
    return result


def _integer(value: Any, where: str, minimum: int = 0, maximum: int | None = None) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        _fail("invalid_value", f"{where} must be an integer >= {minimum}")
    if maximum is not None and value > maximum:
        _fail("invalid_value", f"{where} exceeds {maximum}")
    return value


def _positive_number(value: Any, where: str, maximum: float | None = None) -> float:
    if not _is_number(value) or float(value) <= 0:
        _fail("invalid_value", f"{where} must be a positive finite number")
    result = float(value)
    if maximum is not None and result > maximum:
        _fail("invalid_value", f"{where} exceeds {maximum}")
    return result


def _sha256(value: Any, where: str) -> str:
    result = _string(value, where, maximum=64)
    if SHA256_RE.fullmatch(result) is None:
        _fail("invalid_sha256", f"{where} must be a lowercase SHA-256")
    return result


def _json_load(data: bytes, where: str) -> dict[str, Any]:
    def pairs_hook(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise _DuplicateJSONKey(key)
            result[key] = value
        return result

    def invalid_constant(value: str) -> None:
        raise ValueError(f"non-finite number {value}")

    try:
        decoded = json.loads(
            data.decode("utf-8"),
            object_pairs_hook=pairs_hook,
            parse_constant=invalid_constant,
        )
    except UnicodeDecodeError as error:
        _fail("invalid_utf8", f"{where}: {error}")
    except _DuplicateJSONKey as error:
        _fail("duplicate_json_key", f"{where}: {error}")
    except (json.JSONDecodeError, ValueError) as error:
        _fail("invalid_json", f"{where}: {error}")
    return _object(decoded, where)


def _safe_archive_path(name: str, *, directory: bool) -> str:
    if not name or "\\" in name or name.startswith("/") or "\x00" in name:
        _fail("unsafe_path", f"unsafe ZIP entry path {name!r}")
    if unicodedata.normalize("NFC", name) != name:
        _fail("unicode_not_nfc", f"ZIP entry is not NFC: {name!r}")
    candidate = name[:-1] if directory and name.endswith("/") else name
    if not candidate or candidate.endswith("/"):
        _fail("unsafe_path", f"invalid ZIP entry path {name!r}")
    parts = candidate.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        _fail("unsafe_path", f"unsafe ZIP entry path {name!r}")
    if PurePosixPath(candidate).is_absolute():
        _fail("unsafe_path", f"absolute ZIP entry path {name!r}")
    if any(any(ord(character) < 32 or ord(character) == 127 for character in part) for part in parts):
        _fail("unsafe_path", f"ZIP entry contains a control character: {name!r}")
    for part in parts:
        if part != part.strip() or part.endswith((".", " ")) or ":" in part:
            _fail("unsafe_path", f"ZIP entry is not portable across platforms: {name!r}")
        if part.split(".", 1)[0].casefold() in WINDOWS_RESERVED_NAMES:
            _fail("unsafe_path", f"ZIP entry uses a reserved Windows name: {name!r}")
    return candidate


def _expected_media_type(path: str) -> str:
    if path.endswith(".json"):
        return "application/json"
    if path.endswith(".rgba"):
        return "application/vnd.petsgraph.rgba8"
    _fail("unsupported_media_type", f"unsupported runtime file {path}")


class PetPackValidator:
    def __init__(self, limits: PetPackLimits | None = None):
        self.limits = limits or PetPackLimits()

    def validate(self, package_path: str | Path) -> PetPackValidationReport:
        path = Path(package_path)
        if path.suffix.lower() != ".petpack" or not path.is_file():
            _fail("invalid_container", "input must be one .petpack file")
        archive_bytes = path.stat().st_size
        if archive_bytes <= 0 or archive_bytes > self.limits.max_archive_bytes:
            _fail("archive_budget", "archive byte size is outside the allowed budget")
        with path.open("rb") as handle:
            if handle.read(4) != b"PK\x03\x04":
                _fail("invalid_container", "archive must start with a ZIP local header")
            if archive_bytes < 22:
                _fail("invalid_container", "archive is too short for a ZIP end record")
            tail_size = min(archive_bytes, 65_557)
            handle.seek(-tail_size, 2)
            tail = handle.read(tail_size)
            end_record = tail.rfind(b"PK\x05\x06")
            if end_record < 0 or end_record + 22 > len(tail):
                _fail("invalid_container", "archive has no complete ZIP end record")
            comment_bytes = int.from_bytes(tail[end_record + 20 : end_record + 22], "little")
            if end_record + 22 + comment_bytes != len(tail):
                _fail("invalid_container", "archive contains trailing data after its ZIP end record")

        try:
            archive = zipfile.ZipFile(path, "r")
        except (OSError, zipfile.BadZipFile) as error:
            _fail("invalid_container", str(error))

        with archive:
            infos, info_by_path, uncompressed_bytes = self._validate_archive_index(archive)
            json_cache = self._load_json_files(archive, info_by_path)
            integrity = _json_load(json_cache["integrity.json"], "integrity.json")
            digests = self._verify_integrity(archive, infos, info_by_path, integrity, json_cache)

            manifest = _json_load(json_cache["manifest.json"], "manifest.json")
            manifest_values = self._validate_manifest(manifest)
            graph = _json_load(json_cache["graph.json"], "graph.json")
            behavior = _json_load(json_cache["behavior.json"], "behavior.json")
            clips = {
                clip_path: _json_load(data, clip_path)
                for clip_path, data in json_cache.items()
                if clip_path.startswith("clips/")
            }
            clip_values = self._validate_clips(
                clips, manifest_values["stage"], info_by_path, digests
            )
            graph_values = self._validate_graph(graph, clip_values, manifest_values["default_node"])
            self._validate_behavior(
                behavior,
                graph_values["nodes"],
                graph_values["eligible"],
                manifest_values["default_node"],
            )

            return PetPackValidationReport(
                path=path.name,
                package_id=manifest_values["package_id"],
                pet_id=manifest_values["pet_id"],
                species=manifest_values["species"],
                content_version=manifest_values["content_version"],
                format_version=FORMAT_VERSION,
                archive_bytes=archive_bytes,
                uncompressed_bytes=uncompressed_bytes,
                entry_count=len([info for info in infos if not info.is_dir()]),
                clip_count=len(clip_values),
                node_count=len(graph_values["nodes"]),
                edge_count=graph_values["edge_count"],
                representation_kinds=tuple(
                    sorted({kind for clip in clip_values.values() for kind in clip["kinds"]})
                ),
            )

    def _validate_archive_index(
        self, archive: zipfile.ZipFile
    ) -> tuple[list[zipfile.ZipInfo], dict[str, zipfile.ZipInfo], int]:
        infos = archive.infolist()
        if not infos or len(infos) > self.limits.max_entries:
            _fail("entry_budget", "ZIP entry count is outside the allowed budget")
        if archive.comment:
            _fail("noncanonical_zip", "ZIP comments are not allowed")

        info_by_path: dict[str, zipfile.ZipInfo] = {}
        folded: dict[str, str] = {}
        total = 0
        for info in infos:
            normalized = _safe_archive_path(info.filename, directory=info.is_dir())
            collision_key = unicodedata.normalize("NFC", normalized).casefold()
            if normalized in info_by_path:
                _fail("duplicate_path", f"duplicate ZIP entry {normalized}")
            if collision_key in folded:
                _fail(
                    "casefold_collision",
                    f"ZIP entries collide across platforms: {folded[collision_key]} and {normalized}",
                )
            folded[collision_key] = normalized
            info_by_path[normalized] = info

            if info.flag_bits & 0x1:
                _fail("encrypted_entry", f"encrypted ZIP entry {normalized}")
            if info.compress_type not in ALLOWED_COMPRESSION:
                _fail("unsupported_compression", f"unsupported compression for {normalized}")
            mode = info.external_attr >> 16
            if stat.S_ISLNK(mode):
                _fail("symlink_entry", f"symbolic link entry {normalized}")
            if not info.is_dir() and mode and mode & 0o111:
                _fail("executable_entry", f"executable permission bits on {normalized}")
            if info.is_dir():
                continue
            suffix = PurePosixPath(normalized).suffix.lower()
            if suffix in PROHIBITED_SUFFIXES:
                _fail("executable_entry", f"prohibited executable content {normalized}")
            if info.file_size > self.limits.max_single_entry_bytes:
                _fail("entry_budget", f"entry exceeds byte budget: {normalized}")
            if info.file_size and info.compress_size == 0:
                _fail("compression_ratio", f"invalid compressed size for {normalized}")
            if info.compress_size:
                ratio = info.file_size / info.compress_size
                if ratio > self.limits.max_compression_ratio:
                    _fail("compression_ratio", f"entry compression ratio is too high: {normalized}")
            total += info.file_size
            if total > self.limits.max_uncompressed_bytes:
                _fail("archive_budget", "uncompressed archive exceeds byte budget")

        file_paths = {name for name, info in info_by_path.items() if not info.is_dir()}
        missing = sorted(REQUIRED_ROOT_FILES - file_paths)
        if missing:
            _fail("missing_required_file", f"missing {', '.join(missing)}")
        for name in file_paths:
            parts = name.split("/")
            if len(parts) == 1:
                if name not in REQUIRED_ROOT_FILES:
                    _fail("unexpected_runtime_file", f"unexpected root file {name}")
            elif parts[0] == "clips":
                if len(parts) != 2 or not name.endswith(".json"):
                    _fail("unexpected_runtime_file", f"invalid clip metadata path {name}")
            elif parts[0] == "media":
                if len(parts) != 3 or not name.endswith(".rgba"):
                    _fail("unexpected_runtime_file", f"invalid media path {name}")
            else:
                _fail("unexpected_runtime_file", f"unexpected runtime path {name}")
        return infos, info_by_path, total

    def _load_json_files(
        self, archive: zipfile.ZipFile, info_by_path: Mapping[str, zipfile.ZipInfo]
    ) -> dict[str, bytes]:
        result: dict[str, bytes] = {}
        for name, info in info_by_path.items():
            if info.is_dir() or not name.endswith(".json"):
                continue
            if info.file_size > self.limits.max_json_bytes:
                _fail("json_budget", f"JSON file exceeds byte budget: {name}")
            try:
                result[name] = archive.read(info)
            except (OSError, RuntimeError, zipfile.BadZipFile) as error:
                _fail("corrupt_entry", f"{name}: {error}")
        return result

    def _verify_integrity(
        self,
        archive: zipfile.ZipFile,
        infos: list[zipfile.ZipInfo],
        info_by_path: Mapping[str, zipfile.ZipInfo],
        integrity: Mapping[str, Any],
        json_cache: Mapping[str, bytes],
    ) -> dict[str, str]:
        _keys(integrity, "integrity.json", {"formatVersion", "algorithm", "files"})
        if integrity["formatVersion"] != FORMAT_VERSION or integrity["algorithm"] != "sha256":
            _fail("unsupported_format", "integrity format or algorithm is unsupported")
        entries = _array(integrity["files"], "integrity.files")
        if not entries:
            _fail("integrity_coverage", "integrity.files must not be empty")

        declared: dict[str, dict[str, Any]] = {}
        folded: set[str] = set()
        for index, raw_entry in enumerate(entries):
            entry = _object(raw_entry, f"integrity.files[{index}]")
            _keys(entry, f"integrity.files[{index}]", {"path", "bytes", "mediaType", "sha256"})
            path = _safe_archive_path(_string(entry["path"], f"integrity.files[{index}].path"), directory=False)
            if path == "integrity.json" or path in declared or path.casefold() in folded:
                _fail("integrity_coverage", f"duplicate or self integrity entry {path}")
            folded.add(path.casefold())
            byte_count = _integer(entry["bytes"], f"integrity entry bytes for {path}")
            media_type = _string(entry["mediaType"], f"integrity mediaType for {path}", maximum=120)
            if media_type != _expected_media_type(path):
                _fail("unsupported_media_type", f"incorrect media type for {path}")
            declared[path] = {
                "bytes": byte_count,
                "sha256": _sha256(entry["sha256"], f"integrity SHA-256 for {path}"),
            }

        actual = {
            name
            for name, info in info_by_path.items()
            if not info.is_dir() and name != "integrity.json"
        }
        if set(declared) != actual:
            missing = sorted(actual - declared.keys())
            extra = sorted(declared.keys() - actual)
            _fail(
                "integrity_coverage",
                f"integrity coverage mismatch, missing={missing}, extra={extra}",
            )

        digests: dict[str, str] = {}
        for path in sorted(actual):
            info = info_by_path[path]
            entry = declared[path]
            if info.file_size != entry["bytes"]:
                _fail("integrity_bytes", f"byte count mismatch for {path}")
            digest = hashlib.sha256()
            byte_count = 0
            try:
                if path in json_cache:
                    data = json_cache[path]
                    digest.update(data)
                    byte_count = len(data)
                else:
                    with archive.open(info, "r") as handle:
                        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                            digest.update(chunk)
                            byte_count += len(chunk)
            except (OSError, RuntimeError, zipfile.BadZipFile) as error:
                _fail("corrupt_entry", f"{path}: {error}")
            if byte_count != info.file_size:
                _fail("integrity_bytes", f"read length mismatch for {path}")
            actual_digest = digest.hexdigest()
            if actual_digest != entry["sha256"]:
                _fail("integrity_sha256", f"SHA-256 mismatch for {path}")
            digests[path] = actual_digest
        return digests

    def _validate_manifest(self, manifest: Mapping[str, Any]) -> dict[str, Any]:
        _keys(
            manifest,
            "manifest.json",
            {"formatVersion", "package", "pet", "stage", "capabilities", "graph", "behavior", "integrity"},
        )
        if manifest["formatVersion"] != FORMAT_VERSION:
            _fail("unsupported_format", "only PetPack formatVersion 1.0.0 is supported")
        package = _object(manifest["package"], "manifest.package")
        _keys(package, "manifest.package", {"id", "contentVersion", "createdAt"})
        package_id = _identifier(package["id"], "manifest.package.id", PACKAGE_ID_RE, 80)
        content_version = _string(package["contentVersion"], "manifest.package.contentVersion", maximum=80)
        if SEMVER_RE.fullmatch(content_version) is None:
            _fail("invalid_semver", "manifest.package.contentVersion must be semantic versioning")
        created_at = _string(package["createdAt"], "manifest.package.createdAt", maximum=80)
        try:
            timestamp = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
        except ValueError:
            _fail("invalid_timestamp", "manifest.package.createdAt is not ISO 8601")
        if timestamp.tzinfo is None or timestamp.utcoffset() is None:
            _fail("invalid_timestamp", "manifest.package.createdAt must include an offset")

        pet = _object(manifest["pet"], "manifest.pet")
        _keys(pet, "manifest.pet", {"id", "displayName", "species"})
        pet_id = _identifier(pet["id"], "manifest.pet.id", PACKAGE_ID_RE, 80)
        if pet_id != package_id:
            _fail("identity_mismatch", "manifest pet.id must equal package.id")
        display_name = _string(pet["displayName"], "manifest.pet.displayName", maximum=80)
        species = _string(pet["species"], "manifest.pet.species", maximum=12)
        if species not in {"cat", "dog"}:
            _fail("unsupported_species", "manifest.pet.species must be cat or dog")

        stage = _object(manifest["stage"], "manifest.stage")
        _keys(stage, "manifest.stage", {"referenceCanvasPx", "anchor", "baseDisplayHeight", "defaultNode"})
        canvas = self._two_integers(stage["referenceCanvasPx"], "manifest.stage.referenceCanvasPx", 1, 16384)
        if stage["anchor"] != "bottom-center":
            _fail("unsupported_anchor", "manifest.stage.anchor must be bottom-center")
        base_height = _positive_number(stage["baseDisplayHeight"], "manifest.stage.baseDisplayHeight", 4096)
        default_node = _identifier(stage["defaultNode"], "manifest.stage.defaultNode", NODE_ID_RE, 120)

        capabilities = _object(manifest["capabilities"], "manifest.capabilities")
        _keys(capabilities, "manifest.capabilities", {"required", "optional"})
        required = self._capabilities(capabilities["required"], "manifest.capabilities.required")
        optional = self._capabilities(capabilities["optional"], "manifest.capabilities.optional")
        unknown = sorted(required - SUPPORTED_REQUIRED_CAPABILITIES)
        if unknown:
            _fail("unsupported_capability", f"unknown required capabilities: {unknown}")
        if BASELINE_CAPABILITY not in required:
            _fail("missing_capability", f"required capability {BASELINE_CAPABILITY} is missing")
        if required & optional:
            _fail("invalid_capability", "required and optional capabilities overlap")

        for key, expected in (("graph", "graph.json"), ("behavior", "behavior.json"), ("integrity", "integrity.json")):
            if manifest[key] != expected:
                _fail("noncanonical_path", f"manifest.{key} must be {expected}")
        return {
            "package_id": package_id,
            "pet_id": pet_id,
            "display_name": display_name,
            "species": species,
            "content_version": content_version,
            "default_node": default_node,
            "stage": {"canvas": canvas, "anchor": "bottom-center", "base_height": base_height},
        }

    def _validate_clips(
        self,
        clips: Mapping[str, Mapping[str, Any]],
        manifest_stage: Mapping[str, Any],
        info_by_path: Mapping[str, zipfile.ZipInfo],
        digests: Mapping[str, str],
    ) -> dict[str, dict[str, Any]]:
        if not clips:
            _fail("missing_clip", "package has no clip metadata")
        result: dict[str, dict[str, Any]] = {}
        for clip_path, clip in sorted(clips.items()):
            _keys(
                clip,
                clip_path,
                {
                    "formatVersion", "id", "type", "entryNode", "exitNode", "frameRate",
                    "frameCount", "durationSeconds", "safeExitFrames", "stage", "geometry",
                    "playback", "production", "representations",
                },
            )
            if clip["formatVersion"] != FORMAT_VERSION:
                _fail("unsupported_format", f"{clip_path} formatVersion is unsupported")
            clip_id = _identifier(clip["id"], f"{clip_path}.id", CLIP_ID_RE, 160)
            if clip_path != f"clips/{clip_id}.json":
                _fail("identity_mismatch", f"clip id does not match path {clip_path}")
            if clip_id in result:
                _fail("duplicate_identifier", f"duplicate clip id {clip_id}")
            clip_type = _string(clip["type"], f"{clip_path}.type", maximum=16)
            if clip_type not in {"loop", "transition"}:
                _fail("invalid_clip", f"unsupported clip type {clip_type}")
            entry_node = _identifier(clip["entryNode"], f"{clip_path}.entryNode", NODE_ID_RE, 120)
            exit_node = _identifier(clip["exitNode"], f"{clip_path}.exitNode", NODE_ID_RE, 120)
            if clip_type == "loop" and entry_node != exit_node:
                _fail("invalid_clip", f"loop {clip_id} must return to its entry node")
            if clip_type == "transition" and entry_node == exit_node:
                _fail("invalid_clip", f"transition {clip_id} must change nodes")
            frame_rate = self._frame_rate(clip["frameRate"], f"{clip_path}.frameRate")
            frame_count = _integer(clip["frameCount"], f"{clip_path}.frameCount", 1)
            duration = _positive_number(clip["durationSeconds"], f"{clip_path}.durationSeconds")
            expected_duration = frame_count * frame_rate[1] / frame_rate[0]
            if not math.isclose(duration, expected_duration, rel_tol=0, abs_tol=1e-6):
                _fail("invalid_duration", f"{clip_id} duration does not match frame count and rate")
            safe_exits_raw = _array(clip["safeExitFrames"], f"{clip_path}.safeExitFrames")
            safe_exits = [_integer(value, f"{clip_path}.safeExitFrames", 0, frame_count - 1) for value in safe_exits_raw]
            if safe_exits != sorted(set(safe_exits)):
                _fail("invalid_safe_exit", f"{clip_id} safe exits must be sorted and unique")
            if clip_type == "loop" and not safe_exits:
                _fail("invalid_safe_exit", f"loop {clip_id} needs at least one safe exit")
            if clip_type == "transition" and safe_exits:
                _fail("invalid_safe_exit", f"transition {clip_id} cannot declare safe exits")

            stage = _object(clip["stage"], f"{clip_path}.stage")
            _keys(stage, f"{clip_path}.stage", {"referenceCanvasPx", "anchor"})
            canvas = self._two_integers(stage["referenceCanvasPx"], f"{clip_path}.stage.referenceCanvasPx", 1, 16384)
            if canvas != manifest_stage["canvas"] or stage["anchor"] != "bottom-center":
                _fail("stage_mismatch", f"{clip_id} stage differs from manifest")
            geometry = _object(clip["geometry"], f"{clip_path}.geometry")
            _keys(geometry, f"{clip_path}.geometry", {"cropPx", "presentationOffsetPx"})
            crop = self._four_integers(geometry["cropPx"], f"{clip_path}.geometry.cropPx")
            offset = self._two_integers(geometry["presentationOffsetPx"], f"{clip_path}.geometry.presentationOffsetPx", 0)
            x, y, width, height = crop
            if width <= 0 or height <= 0 or x + width > canvas[0] or y + height > canvas[1]:
                _fail("invalid_geometry", f"{clip_id} crop lies outside the reference canvas")
            if offset != (x, y):
                _fail("invalid_geometry", f"{clip_id} presentation offset must equal crop origin")

            playback = _object(clip["playback"], f"{clip_path}.playback")
            _keys(playback, f"{clip_path}.playback", {"nativeContinuousFrames", "rate", "speedProcessing"})
            if playback != {"nativeContinuousFrames": True, "rate": 1.0, "speedProcessing": "none"}:
                _fail("invalid_playback", f"{clip_id} must use native continuous frames at 1.0x")
            production = _object(clip["production"], f"{clip_path}.production")
            _keys(production, f"{clip_path}.production", {"recipeDigest", "approvalDigest"})
            _sha256(production["recipeDigest"], f"{clip_path}.production.recipeDigest")
            _sha256(production["approvalDigest"], f"{clip_path}.production.approvalDigest")

            representations = _array(clip["representations"], f"{clip_path}.representations")
            if len(representations) != 1:
                _fail("invalid_representation", f"{clip_id} must have exactly one 1.0 baseline representation")
            kinds: set[str] = set()
            for index, raw_representation in enumerate(representations):
                representation = _object(raw_representation, f"{clip_path}.representations[{index}]")
                self._validate_representation(
                    representation,
                    clip_path,
                    clip_id,
                    crop,
                    frame_count,
                    frame_rate,
                    info_by_path,
                    digests,
                )
                kinds.add(representation["kind"])
            if kinds != {BASELINE_CAPABILITY}:
                _fail("missing_representation", f"{clip_id} lacks the baseline representation")
            result[clip_id] = {
                "type": clip_type,
                "entry": entry_node,
                "exit": exit_node,
                "kinds": kinds,
            }

        media_paths = {
            name for name, info in info_by_path.items() if not info.is_dir() and name.startswith("media/")
        }
        declared_media = {
            representation["path"]
            for clip in clips.values()
            for representation in _array(clip["representations"], "clip representations")
        }
        if media_paths != declared_media:
            _fail("media_coverage", "clip representations do not exactly cover media entries")
        return result

    def _validate_representation(
        self,
        representation: Mapping[str, Any],
        clip_path: str,
        clip_id: str,
        crop: tuple[int, int, int, int],
        frame_count: int,
        frame_rate: tuple[int, int],
        info_by_path: Mapping[str, zipfile.ZipInfo],
        digests: Mapping[str, str],
    ) -> None:
        where = f"{clip_path}.representations[0]"
        _keys(
            representation,
            where,
            {
                "id", "kind", "path", "encoding", "widthPx", "heightPx", "bytesPerRow",
                "frameCount", "frameRate", "alpha", "colorSpace", "bytes", "sha256",
            },
        )
        if representation["id"] != BASELINE_CAPABILITY or representation["kind"] != BASELINE_CAPABILITY:
            _fail("invalid_representation", f"{clip_id} representation must be {BASELINE_CAPABILITY}")
        media_path = _safe_archive_path(_string(representation["path"], f"{where}.path"), directory=False)
        expected_path = f"media/{clip_id}/{BASELINE_CAPABILITY}.rgba"
        if media_path != expected_path:
            _fail("noncanonical_path", f"baseline media path must be {expected_path}")
        if representation["encoding"] != "raw-premultiplied-rgba8":
            _fail("invalid_representation", f"{clip_id} has unsupported RGBA encoding")
        width = _integer(representation["widthPx"], f"{where}.widthPx", 1)
        height = _integer(representation["heightPx"], f"{where}.heightPx", 1)
        if (width, height) != (crop[2], crop[3]):
            _fail("invalid_geometry", f"{clip_id} media dimensions differ from fixed crop")
        bytes_per_row = _integer(representation["bytesPerRow"], f"{where}.bytesPerRow", 4)
        if bytes_per_row != width * 4:
            _fail("invalid_representation", f"{clip_id} bytesPerRow must equal width times four")
        if _integer(representation["frameCount"], f"{where}.frameCount", 1) != frame_count:
            _fail("invalid_representation", f"{clip_id} representation frame count differs")
        if self._frame_rate(representation["frameRate"], f"{where}.frameRate") != frame_rate:
            _fail("invalid_representation", f"{clip_id} representation frame rate differs")
        if representation["alpha"] != "premultiplied" or representation["colorSpace"] != "srgb":
            _fail("invalid_representation", f"{clip_id} must use premultiplied sRGB")
        expected_bytes = bytes_per_row * height * frame_count
        declared_bytes = _integer(representation["bytes"], f"{where}.bytes", 1)
        if declared_bytes != expected_bytes:
            _fail("invalid_media_length", f"{clip_id} declared media length is inconsistent")
        info = info_by_path.get(media_path)
        if info is None or info.is_dir() or info.file_size != expected_bytes:
            _fail("invalid_media_length", f"{clip_id} media byte length is inconsistent")
        digest = _sha256(representation["sha256"], f"{where}.sha256")
        if digests.get(media_path) != digest:
            _fail("integrity_sha256", f"{clip_id} representation digest differs from integrity")

    def _validate_graph(
        self,
        graph: Mapping[str, Any],
        clips: Mapping[str, Mapping[str, Any]],
        default_node: str,
    ) -> dict[str, Any]:
        _keys(graph, "graph.json", {"formatVersion", "nodes", "edges"})
        if graph["formatVersion"] != FORMAT_VERSION:
            _fail("unsupported_format", "graph formatVersion is unsupported")
        raw_nodes = _array(graph["nodes"], "graph.nodes")
        if not raw_nodes:
            _fail("invalid_graph", "graph needs at least one node")
        nodes: dict[str, dict[str, Any]] = {}
        eligible: set[str] = set()
        referenced_clips: set[str] = set()
        for index, raw_node in enumerate(raw_nodes):
            node = _object(raw_node, f"graph.nodes[{index}]")
            _keys(node, f"graph.nodes[{index}]", {"id", "role", "scene", "autonomousEligible"}, {"loopClip"})
            node_id = _identifier(node["id"], f"graph.nodes[{index}].id", NODE_ID_RE, 120)
            if node_id in nodes:
                _fail("duplicate_identifier", f"duplicate graph node {node_id}")
            role = _string(node["role"], f"graph node {node_id} role", maximum=16)
            if role not in {"dwell", "gateway"}:
                _fail("invalid_graph", f"node {node_id} has invalid role")
            scene = _identifier(node["scene"], f"graph node {node_id} scene", NODE_ID_RE, 120)
            autonomous = node["autonomousEligible"]
            if not isinstance(autonomous, bool):
                _fail("invalid_graph", f"node {node_id} autonomousEligible must be boolean")
            loop_clip = node.get("loopClip")
            if role == "dwell":
                loop_clip = _identifier(loop_clip, f"graph node {node_id} loopClip", CLIP_ID_RE, 160)
                clip = clips.get(loop_clip)
                if clip is None or clip["type"] != "loop" or clip["entry"] != node_id:
                    _fail("invalid_graph", f"node {node_id} has an invalid loop clip")
                referenced_clips.add(loop_clip)
            elif loop_clip is not None or autonomous:
                _fail("invalid_graph", f"gateway {node_id} cannot loop or be autonomous")
            if autonomous:
                eligible.add(node_id)
            nodes[node_id] = {"role": role, "scene": scene}
        if default_node not in nodes or nodes[default_node]["role"] != "dwell":
            _fail("invalid_graph", "manifest default node must be a dwell node")
        if default_node not in eligible or not eligible:
            _fail("invalid_graph", "default node must be autonomously eligible")

        raw_edges = _array(graph["edges"], "graph.edges")
        edge_ids: set[str] = set()
        adjacency: dict[str, set[str]] = {node_id: set() for node_id in nodes}
        for index, raw_edge in enumerate(raw_edges):
            edge = _object(raw_edge, f"graph.edges[{index}]")
            _keys(edge, f"graph.edges[{index}]", {"id", "from", "to", "clip", "interruptPolicy"})
            edge_id = _identifier(edge["id"], f"graph.edges[{index}].id", CLIP_ID_RE, 160)
            if edge_id in edge_ids:
                _fail("duplicate_identifier", f"duplicate graph edge {edge_id}")
            edge_ids.add(edge_id)
            source = _identifier(edge["from"], f"graph edge {edge_id} from", NODE_ID_RE, 120)
            target = _identifier(edge["to"], f"graph edge {edge_id} to", NODE_ID_RE, 120)
            if source not in nodes or target not in nodes or source == target:
                _fail("invalid_graph", f"edge {edge_id} has invalid endpoints")
            clip_id = _identifier(edge["clip"], f"graph edge {edge_id} clip", CLIP_ID_RE, 160)
            clip = clips.get(clip_id)
            if clip is None or clip["type"] != "transition" or clip["entry"] != source or clip["exit"] != target:
                _fail("invalid_graph", f"edge {edge_id} does not match its transition clip")
            if edge["interruptPolicy"] != "finish-before-retarget":
                _fail("invalid_graph", f"edge {edge_id} has an unsupported interrupt policy")
            referenced_clips.add(clip_id)
            adjacency[source].add(target)
        if referenced_clips != set(clips):
            _fail("clip_coverage", "graph does not exactly reference all runtime clips")

        for source in eligible:
            reachable = {source}
            frontier = [source]
            while frontier:
                current = frontier.pop()
                for target in adjacency[current]:
                    if target not in reachable:
                        reachable.add(target)
                        frontier.append(target)
            missing = sorted(eligible - reachable)
            if missing:
                _fail("unreachable_node", f"autonomous nodes are not mutually reachable from {source}: {missing}")
        return {"nodes": nodes, "eligible": eligible, "edge_count": len(raw_edges)}

    def _validate_behavior(
        self,
        behavior: Mapping[str, Any],
        nodes: Mapping[str, Mapping[str, Any]],
        eligible: set[str],
        default_node: str,
    ) -> None:
        _keys(behavior, "behavior.json", {"formatVersion", "profile", "defaultNode", "timing", "nodeWeights", "sceneWeights"})
        if behavior["formatVersion"] != FORMAT_VERSION:
            _fail("unsupported_format", "behavior formatVersion is unsupported")
        if behavior["profile"] != "passive-memorial-companion" or behavior["defaultNode"] != default_node:
            _fail("invalid_behavior", "behavior profile or default node is inconsistent")
        timing = _object(behavior["timing"], "behavior.timing")
        _keys(timing, "behavior.timing", {"strategy", "dwellRangesSeconds", "avoidImmediateRepeat"})
        if timing["strategy"] != "independent-random-dwell" or not isinstance(timing["avoidImmediateRepeat"], bool):
            _fail("invalid_behavior", "behavior timing strategy is unsupported")
        ranges = _object(timing["dwellRangesSeconds"], "behavior.timing.dwellRangesSeconds")
        if set(ranges) != eligible:
            _fail("invalid_behavior", "dwell ranges must exactly cover autonomous nodes")
        for node_id, raw_range in ranges.items():
            values = _array(raw_range, f"dwell range for {node_id}")
            if len(values) != 2:
                _fail("invalid_behavior", f"dwell range for {node_id} needs min and max")
            minimum = _positive_number(values[0], f"dwell minimum for {node_id}")
            maximum = _positive_number(values[1], f"dwell maximum for {node_id}")
            if minimum > maximum:
                _fail("invalid_behavior", f"dwell range for {node_id} is reversed")
        node_weights = _object(behavior["nodeWeights"], "behavior.nodeWeights")
        if not set(node_weights).issubset(eligible):
            _fail("invalid_behavior", "node weights reference non-autonomous nodes")
        for node_id, weight in node_weights.items():
            _positive_number(weight, f"node weight for {node_id}")
        scenes = {node["scene"] for node in nodes.values()}
        scene_weights = _object(behavior["sceneWeights"], "behavior.sceneWeights")
        if not set(scene_weights).issubset(scenes):
            _fail("invalid_behavior", "scene weights reference unknown scenes")
        for scene, weight in scene_weights.items():
            _positive_number(weight, f"scene weight for {scene}")

    @staticmethod
    def _capabilities(value: Any, where: str) -> set[str]:
        raw = _array(value, where)
        result = {
            _identifier(item, f"{where} item", PACKAGE_ID_RE, 120)
            for item in raw
        }
        if len(result) != len(raw):
            _fail("invalid_capability", f"{where} contains duplicates")
        return result

    @staticmethod
    def _frame_rate(value: Any, where: str) -> tuple[int, int]:
        frame_rate = _object(value, where)
        _keys(frame_rate, where, {"numerator", "denominator"})
        return (
            _integer(frame_rate["numerator"], f"{where}.numerator", 1, 1000),
            _integer(frame_rate["denominator"], f"{where}.denominator", 1, 1000),
        )

    @staticmethod
    def _two_integers(value: Any, where: str, minimum: int, maximum: int | None = None) -> tuple[int, int]:
        raw = _array(value, where)
        if len(raw) != 2:
            _fail("invalid_value", f"{where} must contain two integers")
        return (
            _integer(raw[0], f"{where}[0]", minimum, maximum),
            _integer(raw[1], f"{where}[1]", minimum, maximum),
        )

    @staticmethod
    def _four_integers(value: Any, where: str) -> tuple[int, int, int, int]:
        raw = _array(value, where)
        if len(raw) != 4:
            _fail("invalid_value", f"{where} must contain four integers")
        return tuple(_integer(item, f"{where} item", 0) for item in raw)  # type: ignore[return-value]
