#!/usr/bin/env python3
"""Build a zero-pet Apple-silicon PetsGraph Player application."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
PACKAGE_ROOT = Path(__file__).resolve().parents[1]
APP_ICON = ROOT / "assets" / "brand" / "macos" / "PetsGraph.icns"
SYNTHETIC_FIXTURE = ROOT / "petpack" / "fixtures" / "synthetic-cat-v1.petpack"
SIGNING_DETRITUS_XATTRS = {
    "com.apple.FinderInfo",
    "com.apple.ResourceFork",
    "com.apple.quarantine",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--build-number", default="19")
    parser.add_argument("--app-name", default="PetsGraph")
    parser.add_argument("--bundle-identifier", default="com.maxwell.petsgraph")
    return parser.parse_args()


def safe_output_path(path: Path, *, strict: bool) -> Path:
    result = path if path.is_absolute() else ROOT / path
    result = result.resolve(strict=strict)
    allowed_roots = (
        ROOT,
        Path("/tmp").resolve(),
        Path(tempfile.gettempdir()).resolve(),
    )
    if not any(result == root or result.is_relative_to(root) for root in allowed_roots):
        raise ValueError("--output must stay inside the repository or the system temporary directory")
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
        raise ValueError("app contains signing-hostile metadata: " + ", ".join(remaining))


def main() -> None:
    args = parse_args()
    output = safe_output_path(args.output, strict=False)
    if output.exists():
        raise FileExistsError(f"refusing to overwrite existing app: {output}")
    if output.suffix != ".app":
        raise ValueError("--output must end in .app")
    if not args.bundle_identifier or any(character.isspace() for character in args.bundle_identifier):
        raise ValueError("--bundle-identifier must not contain spaces")
    app_name = args.app_name.strip()
    if not app_name or "/" in app_name or ":" in app_name:
        raise ValueError("--app-name must be a file-safe name")
    if not APP_ICON.is_file() or not SYNTHETIC_FIXTURE.is_file():
        raise FileNotFoundError("public app icon or synthetic PetPack fixture is missing")
    output.parent.mkdir(parents=True, exist_ok=True)

    environment = os.environ.copy()
    environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    environment.setdefault("CLANG_MODULE_CACHE_PATH", "/tmp/petsgraph-clang-module-cache")
    environment.setdefault("SWIFTPM_MODULECACHE_OVERRIDE", "/tmp/petsgraph-swiftpm-module-cache")
    environment.setdefault("CFFIXED_USER_HOME", "/tmp/petsgraph-cf-home")
    for key in ("CLANG_MODULE_CACHE_PATH", "SWIFTPM_MODULECACHE_OVERRIDE", "CFFIXED_USER_HOME"):
        Path(environment[key]).mkdir(parents=True, exist_ok=True)

    swift_build = ["/usr/bin/xcrun", "swift", "build", "--disable-sandbox", "-c", "release"]
    subprocess.run(swift_build, cwd=PACKAGE_ROOT, env=environment, check=True)
    bin_path = subprocess.run(
        [*swift_build, "--show-bin-path"],
        cwd=PACKAGE_ROOT,
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
    if "arm64" not in architecture or "x86_64" in architecture:
        raise ValueError("release executable must be Apple silicon arm64 only")
    subprocess.run(
        [str(binary), "--validate-only", str(SYNTHETIC_FIXTURE)],
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
        shutil.copy2(APP_ICON, resources / APP_ICON.name)
        destination_binary = macos / "petsgraph"
        shutil.copy2(binary, destination_binary)
        destination_binary.chmod(0o755)
        info = {
            "CFBundleDevelopmentRegion": "zh_CN",
            "CFBundleDisplayName": app_name,
            "CFBundleDocumentTypes": [
                {
                    "CFBundleTypeName": "PetsGraph PetPack",
                    "CFBundleTypeRole": "Viewer",
                    "LSHandlerRank": "Owner",
                    "LSItemContentTypes": ["com.maxwell.petsgraph.petpack"],
                }
            ],
            "CFBundleExecutable": "petsgraph",
            "CFBundleIdentifier": args.bundle_identifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleIconFile": "PetsGraph",
            "CFBundleName": app_name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": args.version,
            "CFBundleVersion": args.build_number,
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": True,
            "NSHighResolutionCapable": True,
            "UTExportedTypeDeclarations": [
                {
                    "UTTypeConformsTo": ["public.zip-archive"],
                    "UTTypeDescription": "PetsGraph PetPack",
                    "UTTypeIdentifier": "com.maxwell.petsgraph.petpack",
                    "UTTypeTagSpecification": {
                        "public.filename-extension": ["petpack"],
                    },
                }
            ],
        }
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump(info, handle, sort_keys=True)
        if list(temporary.rglob("*.petpack")) or (resources / "Pets").exists():
            raise ValueError("zero-pet Player build unexpectedly contains pet media")
        remove_signing_detritus(temporary)
        assert_no_signing_detritus(temporary)
        subprocess.run(
            ["/usr/bin/codesign", "--force", "--deep", "--sign", "-", "--timestamp=none", str(temporary)],
            cwd=ROOT,
            env=environment,
            check=True,
        )
        subprocess.run(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(temporary)],
            cwd=ROOT,
            env=environment,
            check=True,
        )
        temporary.rename(output)
        remove_signing_detritus(output)
        assert_no_signing_detritus(output)
        subprocess.run(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(output)],
            cwd=ROOT,
            env=environment,
            check=True,
        )
        subprocess.run(
            [str(output / "Contents" / "MacOS" / "petsgraph"), "--validate-only", str(SYNTHETIC_FIXTURE)],
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
