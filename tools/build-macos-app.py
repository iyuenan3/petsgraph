#!/usr/bin/env python3
"""Build a local versioned petsgraph .app with one bundled pet package."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", default="1")
    parser.add_argument(
        "--bundle-identifier",
        default="com.maxwell.petsgraph.quiet-companion",
    )
    return parser.parse_args()


def within_repo(path: Path, *, strict: bool) -> Path:
    result = path if path.is_absolute() else ROOT / path
    result = result.resolve(strict=strict)
    result.relative_to(ROOT)
    return result


def main() -> None:
    args = parse_args()
    package = within_repo(args.package, strict=True)
    if not package.is_dir() or package.suffix != ".petsgraph-pet":
        raise ValueError("--package must be a .petsgraph-pet directory")
    output = within_repo(args.output, strict=False)
    if output.exists():
        raise FileExistsError(f"refusing to overwrite existing app: {output}")
    if output.suffix != ".app":
        raise ValueError("--output must end in .app")
    if not args.bundle_identifier or any(
        character.isspace() for character in args.bundle_identifier
    ):
        raise ValueError("--bundle-identifier must be a non-empty identifier without spaces")
    output.parent.mkdir(parents=True, exist_ok=True)

    environment = os.environ.copy()
    environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    environment.setdefault("CLANG_MODULE_CACHE_PATH", "/tmp/petsgraph-clang-module-cache")
    environment.setdefault("SWIFTPM_MODULECACHE_OVERRIDE", "/tmp/petsgraph-swiftpm-module-cache")
    environment.setdefault("CFFIXED_USER_HOME", "/tmp/petsgraph-cf-home")
    for key in (
        "CLANG_MODULE_CACHE_PATH",
        "SWIFTPM_MODULECACHE_OVERRIDE",
        "CFFIXED_USER_HOME",
    ):
        Path(environment[key]).mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "/usr/bin/xcrun",
            "swift",
            "build",
            "--disable-sandbox",
            "-c",
            "release",
        ],
        cwd=ROOT,
        env=environment,
        check=True,
    )
    binary = ROOT / ".build" / "release" / "petsgraph"
    if not binary.is_file():
        raise FileNotFoundError(f"release executable not found: {binary}")
    subprocess.run(
        [str(binary), str(package), "--validate-only"],
        cwd=ROOT,
        env=environment,
        check=True,
    )

    temporary = Path(tempfile.mkdtemp(prefix=f"{output.name}.build-", dir=output.parent))
    try:
        contents = temporary / "Contents"
        macos = contents / "MacOS"
        resources = contents / "Resources"
        macos.mkdir(parents=True)
        resources.mkdir(parents=True)
        destination_binary = macos / "petsgraph"
        shutil.copy2(binary, destination_binary)
        destination_binary.chmod(0o755)
        shutil.copytree(package, resources / "DefaultPet.petsgraph-pet")
        info = {
            "CFBundleDevelopmentRegion": "zh_CN",
            "CFBundleDisplayName": "李五百睡觉陪伴",
            "CFBundleExecutable": "petsgraph",
            "CFBundleIdentifier": args.bundle_identifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "petsgraph",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": args.version,
            "CFBundleVersion": args.build_number,
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": True,
            "NSHighResolutionCapable": True,
        }
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump(info, handle, sort_keys=True)
        subprocess.run(
            [
                "/usr/bin/codesign",
                "--force",
                "--deep",
                "--sign",
                "-",
                "--timestamp=none",
                str(temporary),
            ],
            cwd=ROOT,
            env=environment,
            check=True,
        )
        subprocess.run(
            [
                "/usr/bin/codesign",
                "--verify",
                "--deep",
                "--strict",
                "--verbose=2",
                str(temporary),
            ],
            cwd=ROOT,
            env=environment,
            check=True,
        )
        temporary.rename(output)
    except Exception:
        if temporary.exists():
            shutil.rmtree(temporary)
        raise
    print(output)


if __name__ == "__main__":
    main()
