from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MANAGE_PATH = REPOSITORY_ROOT / "codexpets" / "tools" / "manage.py"
SPEC = importlib.util.spec_from_file_location("codexpets_manage", MANAGE_PATH)
assert SPEC is not None and SPEC.loader is not None
MANAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MANAGE)


class CodexPetsManageTests(unittest.TestCase):
    def test_public_packages_match_manifest(self) -> None:
        records = MANAGE.validate_repository(
            MANAGE.DEFAULT_ASSET_ROOT,
            MANAGE.DEFAULT_MANIFEST,
        )
        self.assertEqual(
            [record["id"] for record in records],
            ["wubai-v0", "feiliu-hatch-native-v1"],
        )

    def test_install_is_idempotent(self) -> None:
        records = MANAGE.validate_repository(
            MANAGE.DEFAULT_ASSET_ROOT,
            MANAGE.DEFAULT_MANIFEST,
        )
        with tempfile.TemporaryDirectory(prefix="petsgraph-codexpets-") as directory:
            codex_home = Path(directory)
            MANAGE.install_packages(
                MANAGE.DEFAULT_ASSET_ROOT,
                records,
                [],
                codex_home,
                False,
            )
            MANAGE.install_packages(
                MANAGE.DEFAULT_ASSET_ROOT,
                records,
                [],
                codex_home,
                False,
            )
            for record in records:
                package_id = str(record["id"])
                self.assertTrue(
                    MANAGE.package_matches(
                        MANAGE.DEFAULT_ASSET_ROOT / package_id,
                        codex_home / "pets" / package_id,
                    )
                )

    def test_multi_pet_install_rolls_back_when_later_copy_fails(self) -> None:
        records = MANAGE.validate_repository(
            MANAGE.DEFAULT_ASSET_ROOT,
            MANAGE.DEFAULT_MANIFEST,
        )
        real_copy = MANAGE.shutil.copy2
        calls = 0

        def failing_copy(source: Path, destination: Path) -> Path:
            nonlocal calls
            calls += 1
            if calls == 3:
                raise OSError("simulated second-pet copy failure")
            return real_copy(source, destination)

        with tempfile.TemporaryDirectory(prefix="petsgraph-codexpets-rollback-") as directory:
            codex_home = Path(directory)
            with mock.patch.object(MANAGE.shutil, "copy2", side_effect=failing_copy):
                with self.assertRaises(OSError):
                    MANAGE.install_packages(
                        MANAGE.DEFAULT_ASSET_ROOT,
                        records,
                        [],
                        codex_home,
                        False,
                    )
            pets_root = codex_home / "pets"
            self.assertEqual(list(pets_root.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
