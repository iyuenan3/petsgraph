#!/usr/bin/env python3
"""Build a versioned Apple-silicon PetsGraph app with bundled pet packages."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SIGNING_DETRITUS_XATTRS = {
    "com.apple.FinderInfo",
    "com.apple.ResourceFork",
    "com.apple.quarantine",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--package",
        type=Path,
        action="append",
        required=True,
        help="repeat once for every bundled .petsgraph-pet package",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", default="1")
    parser.add_argument("--app-name", default="PetsGraph")
    parser.add_argument(
        "--bundle-identifier",
        default="com.maxwell.petsgraph",
    )
    return parser.parse_args()


def within_repo(path: Path, *, strict: bool) -> Path:
    result = path if path.is_absolute() else ROOT / path
    result = result.resolve(strict=strict)
    result.relative_to(ROOT)
    return result


def remove_signing_detritus(root: Path) -> None:
    for name in sorted(SIGNING_DETRITUS_XATTRS):
        subprocess.run(
            ["/usr/bin/xattr", "-dr", name, str(root)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def assert_no_signing_detritus(root: Path) -> None:
    result = subprocess.run(
        ["/usr/bin/xattr", "-lr", str(root)],
        check=True,
        capture_output=True,
        text=True,
    )
    remaining = [
        name for name in sorted(SIGNING_DETRITUS_XATTRS)
        if f"{name}:" in result.stdout
    ]
    if remaining:
        raise ValueError(
            "app contains Finder metadata rejected by codesign: "
            + ", ".join(remaining)
        )


def clone_or_copytree(source: Path, destination: Path) -> None:
    """Prefer an APFS clone so local review apps do not duplicate pet media."""
    copy_environment = os.environ.copy()
    copy_environment["COPYFILE_DISABLE"] = "1"
    cloned = subprocess.run(
        ["/bin/cp", "-cR", str(source), str(destination)],
        check=False,
        env=copy_environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if cloned.returncode != 0:
        shutil.copytree(source, destination, copy_function=shutil.copyfile)


def main() -> None:
    args = parse_args()
    packages = [within_repo(value, strict=True) for value in args.package]
    if any(not package.is_dir() or package.suffix != ".petsgraph-pet" for package in packages):
        raise ValueError("every --package must be a .petsgraph-pet directory")
    if len({package.name for package in packages}) != len(packages):
        raise ValueError("bundled pet package directory names must be unique")
    output = within_repo(args.output, strict=False)
    if output.exists():
        raise FileExistsError(f"refusing to overwrite existing app: {output}")
    if output.suffix != ".app":
        raise ValueError("--output must end in .app")
    if not args.bundle_identifier or any(
        character.isspace() for character in args.bundle_identifier
    ):
        raise ValueError("--bundle-identifier must be a non-empty identifier without spaces")
    app_name = args.app_name.strip()
    if not app_name or "/" in app_name or ":" in app_name:
        raise ValueError("--app-name must be a non-empty macOS file-safe name")
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
    swift_build = [
        "/usr/bin/xcrun",
        "swift",
        "build",
        "--disable-sandbox",
        "-c",
        "release",
    ]
    subprocess.run(
        swift_build,
        cwd=ROOT,
        env=environment,
        check=True,
    )
    bin_path = subprocess.run(
        [*swift_build, "--show-bin-path"],
        cwd=ROOT,
        env=environment,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    binary = Path(bin_path) / "petsgraph"
    if not binary.is_file():
        raise FileNotFoundError(f"release executable not found: {binary}")
    architecture = subprocess.run(
        ["/usr/bin/file", str(binary)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    if "arm64" not in architecture:
        raise ValueError("release executable is not Apple silicon arm64")
    subprocess.run(
        [str(binary), *[str(package) for package in packages], "--validate-only"],
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
        pets = resources / "Pets"
        pets.mkdir()
        for package in packages:
            clone_or_copytree(package, pets / package.name)
        info = {
            "CFBundleDevelopmentRegion": "zh_CN",
            "CFBundleDisplayName": app_name,
            "CFBundleExecutable": "petsgraph",
            "CFBundleIdentifier": args.bundle_identifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": app_name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": args.version,
            "CFBundleVersion": args.build_number,
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": True,
            "NSHighResolutionCapable": True,
        }
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump(info, handle, sort_keys=True)
        remove_signing_detritus(temporary)
        assert_no_signing_detritus(temporary)
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
        remove_signing_detritus(output)
        assert_no_signing_detritus(output)
        subprocess.run(
            [
                "/usr/bin/codesign",
                "--verify",
                "--deep",
                "--strict",
                "--verbose=2",
                str(output),
            ],
            cwd=ROOT,
            env=environment,
            check=True,
        )
    except Exception:
        if temporary.exists():
            shutil.rmtree(temporary)
        raise
    print(output)


if __name__ == "__main__":
    main()
