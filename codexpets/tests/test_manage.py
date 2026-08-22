from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest


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


if __name__ == "__main__":
    unittest.main()
