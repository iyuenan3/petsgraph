from __future__ import annotations

import hashlib
import json
import stat
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path
from typing import Callable
from unittest import mock

from petpack.tools.build_fixture import canonical_json, fixture_entries, write_fixture
from petpack.validator import PetPackLimits, PetPackValidationError, PetPackValidator


def rewrite_integrity(entries: dict[str, bytes]) -> None:
    files = []
    for path, data in sorted(entries.items()):
        if path == "integrity.json":
            continue
        files.append(
            {
                "bytes": len(data),
                "mediaType": (
                    "application/json"
                    if path.endswith(".json")
                    else "application/vnd.petsgraph.rgba8"
                ),
                "path": path,
                "sha256": hashlib.sha256(data).hexdigest(),
            }
        )
    entries["integrity.json"] = canonical_json(
        {"algorithm": "sha256", "files": files, "formatVersion": "1.0.0"}
    )


def write_entries(
    output: Path,
    entries: dict[str, bytes],
    *,
    compression: int = zipfile.ZIP_DEFLATED,
    extras: list[tuple[str, bytes, int]] | None = None,
    comment: bytes = b"",
    entry_comment: bytes = b"",
) -> None:
    def raw_info(path: str, mode: int) -> zipfile.ZipInfo:
        # ZipInfo normalizes backslashes on Windows. Assign the stored name after
        # construction so security tests exercise the exact archive bytes on every OS.
        info = zipfile.ZipInfo("placeholder", (2026, 1, 1, 0, 0, 0))
        info.orig_filename = path
        info.filename = path
        info.create_system = 3
        info.external_attr = mode << 16
        info.compress_type = compression
        return info

    with zipfile.ZipFile(output, "w", compression=compression, allowZip64=True) as archive:
        for index, (path, data) in enumerate(sorted(entries.items())):
            info = raw_info(path, 0o100644)
            if index == 0:
                info.comment = entry_comment
            archive.writestr(info, data)
        for path, data, mode in extras or []:
            archive.writestr(raw_info(path, mode), data)
        archive.comment = comment


class PetPackValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="petpack-tests-")
        self.root = Path(self.temp.name)
        self.valid = self.root / "valid.petpack"
        write_fixture(self.valid)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def assert_failure(self, package: Path, code: str) -> PetPackValidationError:
        with self.assertRaises(PetPackValidationError) as context:
            PetPackValidator().validate(package)
        self.assertEqual(context.exception.code, code)
        return context.exception

    def semantic_mutation(
        self, name: str, mutate: Callable[[dict[str, bytes]], None]
    ) -> Path:
        entries = fixture_entries()
        mutate(entries)
        rewrite_integrity(entries)
        output = self.root / name
        write_entries(output, entries)
        return output

    def test_valid_deflate_fixture(self) -> None:
        package = self.root / "deflate.petpack"
        write_fixture(package, compression=zipfile.ZIP_DEFLATED)
        report = PetPackValidator().validate(package)
        self.assertEqual(report.package_id, "synthetic-cat-v1")
        self.assertEqual(report.clip_count, 4)
        self.assertEqual(report.node_count, 2)
        self.assertEqual(report.edge_count, 2)
        self.assertEqual(report.representation_kinds, ("cropped-rgba-clips",))

    def test_valid_stored_fixture(self) -> None:
        self.assertEqual(PetPackValidator().validate(self.valid).clip_count, 4)

    def test_accepts_unknown_optional_capability_and_sparse_weights(self) -> None:
        package = self.root / "forward-compatible.petpack"
        write_fixture(package, forward_compatible=True)
        report = PetPackValidator().validate(package)
        self.assertEqual(report.package_id, "synthetic-cat-forward-v1")
        self.assertEqual(report.clip_count, 4)

    def test_fixture_build_is_deterministic(self) -> None:
        first = self.root / "first.petpack"
        second = self.root / "second.petpack"
        write_fixture(first)
        write_fixture(second)
        self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_cli_prints_valid_json(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "petpack.validator", str(self.valid)],
            check=True,
            capture_output=True,
            text=True,
        )
        report = json.loads(result.stdout)
        self.assertTrue(report["valid"])
        self.assertEqual(report["entry_count"], 12)
        self.assertEqual(report["path"], "valid.petpack")
        self.assertNotIn("display_name", report)
        self.assertNotIn(str(self.root), result.stdout)

    def test_rejects_path_traversal(self) -> None:
        package = self.root / "traversal.petpack"
        write_entries(
            package,
            fixture_entries(),
            extras=[("../escape.json", b"{}", stat.S_IFREG | 0o644)],
        )
        self.assert_failure(package, "unsafe_path")

    def test_rejects_backslash_path(self) -> None:
        package = self.root / "backslash.petpack"
        write_entries(
            package,
            fixture_entries(),
            extras=[("media\\escape.rgba", b"x", stat.S_IFREG | 0o644)],
        )
        with zipfile.ZipFile(package) as archive:
            self.assertIn(
                "media\\escape.rgba",
                [info.orig_filename for info in archive.infolist()],
            )
        with mock.patch.object(zipfile.os, "sep", "\\"):
            self.assert_failure(package, "unsafe_path")

    def test_rejects_casefold_collision(self) -> None:
        package = self.root / "casefold.petpack"
        write_entries(
            package,
            fixture_entries(),
            extras=[("Graph.json", b"{}", stat.S_IFREG | 0o644)],
        )
        self.assert_failure(package, "casefold_collision")

    def test_rejects_duplicate_zip_entry(self) -> None:
        package = self.root / "duplicate.petpack"
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            write_entries(
                package,
                fixture_entries(),
                extras=[("graph.json", b"{}", stat.S_IFREG | 0o644)],
            )
        self.assert_failure(package, "duplicate_path")

    def test_rejects_symlink(self) -> None:
        package = self.root / "symlink.petpack"
        write_entries(
            package,
            fixture_entries(),
            extras=[("media/link.rgba", b"target", stat.S_IFLNK | 0o777)],
        )
        self.assert_failure(package, "symlink_entry")

    def test_rejects_executable_content(self) -> None:
        package = self.root / "executable.petpack"
        write_entries(
            package,
            fixture_entries(),
            extras=[("payload.py", b"pass\n", stat.S_IFREG | 0o644)],
        )
        self.assert_failure(package, "executable_entry")

    def test_rejects_executable_permission_bits(self) -> None:
        package = self.root / "executable-mode.petpack"
        write_entries(
            package,
            fixture_entries(),
            extras=[("media/extra/payload.rgba", b"data", stat.S_IFREG | 0o755)],
        )
        self.assert_failure(package, "executable_entry")

    def test_rejects_explicit_directory_entry(self) -> None:
        package = self.root / "directory-entry.petpack"
        write_entries(
            package,
            fixture_entries(),
            extras=[("media/", b"", stat.S_IFDIR | 0o755)],
        )
        self.assert_failure(package, "noncanonical_zip")

    def test_rejects_symlinked_source_archive(self) -> None:
        linked = self.root / "linked.petpack"
        linked.symlink_to(self.valid)
        self.assert_failure(linked, "invalid_container")

    def test_rejects_windows_reserved_path(self) -> None:
        package = self.root / "reserved.petpack"
        write_entries(
            package,
            fixture_entries(),
            extras=[("clips/CON.json", b"{}", stat.S_IFREG | 0o644)],
        )
        self.assert_failure(package, "unsafe_path")

    def test_rejects_unsupported_compression(self) -> None:
        package = self.root / "bzip2.petpack"
        write_entries(package, fixture_entries(), compression=zipfile.ZIP_BZIP2)
        self.assert_failure(package, "unsupported_compression")

    def test_rejects_integrity_coverage_gap(self) -> None:
        entries = fixture_entries()
        integrity = json.loads(entries["integrity.json"])
        integrity["files"] = integrity["files"][:-1]
        entries["integrity.json"] = canonical_json(integrity)
        package = self.root / "coverage.petpack"
        write_entries(package, entries)
        self.assert_failure(package, "integrity_coverage")

    def test_rejects_media_digest_mismatch(self) -> None:
        entries = fixture_entries()
        path = "media/rest-primary-loop/cropped-rgba-clips.rgba"
        entries[path] = entries[path][:-1] + bytes([entries[path][-1] ^ 0xFF])
        package = self.root / "digest.petpack"
        write_entries(package, entries)
        self.assert_failure(package, "integrity_sha256")

    def test_rejects_duplicate_json_key(self) -> None:
        entries = fixture_entries()
        entries["manifest.json"] = b'{"formatVersion":"1.0.0","formatVersion":"1.0.0"}\n'
        rewrite_integrity(entries)
        package = self.root / "duplicate-json.petpack"
        write_entries(package, entries)
        self.assert_failure(package, "duplicate_json_key")

    def test_rejects_unknown_required_capability(self) -> None:
        def mutate(entries: dict[str, bytes]) -> None:
            manifest = json.loads(entries["manifest.json"])
            manifest["capabilities"]["required"].append("future-decoder")
            entries["manifest.json"] = canonical_json(manifest)

        package = self.semantic_mutation("capability.petpack", mutate)
        self.assert_failure(package, "unsupported_capability")

    def test_rejects_nonportable_semantic_versions(self) -> None:
        for index, version in enumerate(
            ["1.0.0-01", "1.0.0-alpha..1", "2147483648.0.0"]
        ):
            def mutate(entries: dict[str, bytes], value: str = version) -> None:
                manifest = json.loads(entries["manifest.json"])
                manifest["package"]["contentVersion"] = value
                entries["manifest.json"] = canonical_json(manifest)

            package = self.semantic_mutation(f"semver-{index}.petpack", mutate)
            self.assert_failure(package, "invalid_semver")

    def test_rejects_gateway_with_explicit_null_loop(self) -> None:
        def mutate(entries: dict[str, bytes]) -> None:
            graph = json.loads(entries["graph.json"])
            graph["nodes"].append(
                {
                    "autonomousEligible": False,
                    "id": "rest.gateway",
                    "loopClip": None,
                    "role": "gateway",
                    "scene": "rest",
                }
            )
            entries["graph.json"] = canonical_json(graph)

        package = self.semantic_mutation("gateway-null.petpack", mutate)
        self.assert_failure(package, "invalid_graph")

    def test_rejects_frame_count_outside_portable_integer_range(self) -> None:
        def mutate(entries: dict[str, bytes]) -> None:
            path = "clips/rest-primary-loop.json"
            clip = json.loads(entries[path])
            clip["frameCount"] = 2_147_483_648
            entries[path] = canonical_json(clip)

        package = self.semantic_mutation("frame-count-overflow.petpack", mutate)
        self.assert_failure(package, "invalid_value")

    def test_rejects_unreachable_autonomous_node(self) -> None:
        def mutate(entries: dict[str, bytes]) -> None:
            graph = json.loads(entries["graph.json"])
            graph["edges"] = graph["edges"][:1]
            entries["graph.json"] = canonical_json(graph)
            del entries["clips/rest-secondary-to-rest-primary.json"]
            del entries["media/rest-secondary-to-rest-primary/cropped-rgba-clips.rgba"]

        package = self.semantic_mutation("unreachable.petpack", mutate)
        self.assert_failure(package, "unreachable_node")

    def test_rejects_inconsistent_media_length(self) -> None:
        def mutate(entries: dict[str, bytes]) -> None:
            path = "clips/rest-primary-loop.json"
            clip = json.loads(entries[path])
            clip["representations"][0]["bytes"] += 4
            entries[path] = canonical_json(clip)

        package = self.semantic_mutation("length.petpack", mutate)
        self.assert_failure(package, "invalid_media_length")

    def test_rejects_archive_comment(self) -> None:
        package = self.root / "comment.petpack"
        write_entries(package, fixture_entries(), comment=b"not canonical")
        self.assert_failure(package, "noncanonical_zip")

    def test_rejects_entry_comment(self) -> None:
        package = self.root / "entry-comment.petpack"
        write_entries(package, fixture_entries(), entry_comment=b"not canonical")
        self.assert_failure(package, "noncanonical_zip")

    def test_rejects_strong_encryption_flag(self) -> None:
        package = self.root / "strong-encryption.petpack"
        data = bytearray(self.valid.read_bytes())
        end = len(data) - 22
        central = int.from_bytes(data[end + 16 : end + 20], "little")
        local = int.from_bytes(data[central + 42 : central + 46], "little")
        central_flags = int.from_bytes(data[central + 8 : central + 10], "little") | 0x40
        local_flags = int.from_bytes(data[local + 6 : local + 8], "little") | 0x40
        data[central + 8 : central + 10] = central_flags.to_bytes(2, "little")
        data[local + 6 : local + 8] = local_flags.to_bytes(2, "little")
        package.write_bytes(data)
        self.assert_failure(package, "encrypted_entry")

    def test_rejects_gap_before_central_directory(self) -> None:
        package = self.root / "archive-gap.petpack"
        data = bytearray(self.valid.read_bytes())
        end = len(data) - 22
        central = int.from_bytes(data[end + 16 : end + 20], "little")
        data[central:central] = b"x"
        shifted_end = end + 1
        data[shifted_end + 16 : shifted_end + 20] = (central + 1).to_bytes(4, "little")
        package.write_bytes(data)
        self.assert_failure(package, "archive_gap")

    def test_rejects_executable_prefix_before_zip(self) -> None:
        package = self.root / "prefixed.petpack"
        package.write_bytes(b"MZ" + self.valid.read_bytes())
        self.assert_failure(package, "invalid_container")

    def test_rejects_trailing_payload_after_zip(self) -> None:
        package = self.root / "trailing.petpack"
        package.write_bytes(self.valid.read_bytes() + b"trailing payload")
        self.assert_failure(package, "invalid_container")

    def test_applies_entry_budget_before_content_validation(self) -> None:
        limits = PetPackLimits(max_entries=1)
        with self.assertRaises(PetPackValidationError) as context:
            PetPackValidator(limits).validate(self.valid)
        self.assertEqual(context.exception.code, "entry_budget")

    def test_schema_files_are_valid_json(self) -> None:
        schema_root = Path(__file__).resolve().parents[1] / "schema"
        schemas = sorted(schema_root.glob("*.schema.json"))
        self.assertEqual(len(schemas), 5)
        for schema in schemas:
            decoded = json.loads(schema.read_text(encoding="utf-8"))
            self.assertEqual(decoded["$schema"], "https://json-schema.org/draft/2020-12/schema")
        clip = json.loads((schema_root / "clip.schema.json").read_text(encoding="utf-8"))
        self.assertEqual(clip["properties"]["representations"]["maxItems"], 1)
        self.assertEqual(clip["properties"]["frameCount"]["maximum"], 2_147_483_647)


if __name__ == "__main__":
    unittest.main()
