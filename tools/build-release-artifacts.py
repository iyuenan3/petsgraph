#!/usr/bin/env python3
"""Build versioned Apple Silicon release artifacts for PetsGraph."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SIGNING_DETRITUS_XATTRS = (
    "com.apple.FinderInfo",
    "com.apple.ResourceFork",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--app-name", default="PetsGraph")
    return parser.parse_args()


def within_repo(path: Path, *, strict: bool) -> Path:
    resolved = path if path.is_absolute() else ROOT / path
    resolved = resolved.resolve(strict=strict)
    resolved.relative_to(ROOT)
    return resolved


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_package_child(package: Path, relative: str) -> Path:
    candidate = Path(relative)
    if not relative or candidate.is_absolute() or any(
        part in ("", ".", "..") for part in candidate.parts
    ):
        raise ValueError(f"unsafe embedded package path: {relative}")
    result = (package / candidate).resolve(strict=True)
    result.relative_to(package.resolve(strict=True))
    return result


def read_embedded_pet_metadata(app: Path) -> dict[str, object]:
    pets_root = app / "Contents" / "Resources" / "Pets"
    if not pets_root.is_dir():
        raise ValueError("release app must contain Contents/Resources/Pets")
    packages = sorted(
        path for path in pets_root.iterdir()
        if path.is_dir() and path.suffix == ".petsgraph-pet" and not path.name.startswith(".")
    )
    if not packages:
        raise ValueError("release app must contain at least one pet package")

    embedded: list[dict[str, object]] = []
    pet_ids: set[str] = set()
    schema_versions: set[str] = set()
    render_modes: set[str] = set()
    for package in packages:
        payload = json.loads((package / "package.json").read_text(encoding="utf-8"))
        pet = payload.get("pet", {})
        identity = str(pet.get("id", "")).strip()
        name = str(pet.get("displayName", "")).strip()
        if not identity or not name:
            raise ValueError(f"embedded package {package.name} needs pet id and displayName")
        if identity in pet_ids:
            raise ValueError(f"duplicate embedded pet id: {identity}")
        pet_ids.add(identity)

        package_identity = payload.get("package", {})
        package_version = str(package_identity.get("version", ""))
        if not package_version:
            raise ValueError(f"embedded package {package.name} needs a package version")
        review_path = safe_package_child(package, str(payload.get("reviewIndex", "")))
        review = json.loads(review_path.read_text(encoding="utf-8"))
        if review.get("runtimeChainStatus") != "runtime-chain-approved":
            raise ValueError(f"embedded package {package.name} is not runtime-chain-approved")
        if review.get("installable") is not True:
            raise ValueError(f"embedded package {package.name} is not installable")
        if review.get("remainingRuntimeGates"):
            raise ValueError(f"embedded package {package.name} still has runtime gates")

        schema_version = str(payload.get("schemaVersion", ""))
        render_mode = str(payload.get("renderAssets", {}).get("mode", ""))
        schema_versions.add(schema_version)
        render_modes.add(render_mode)
        embedded.append({
            "id": identity,
            "displayName": name,
            "packageId": str(package_identity.get("id", "")),
            "packageVersion": package_version,
            "schemaVersion": schema_version,
            "renderMode": render_mode,
        })

    return {
        "embeddedPets": embedded,
        "packageSchemaVersions": sorted(schema_versions),
        "renderModes": sorted(render_modes),
        "runtimeChainStatus": "runtime-chain-approved",
        "installable": True,
    }


def artifact_entry(path: Path, kind: str) -> dict[str, object]:
    return {
        "kind": kind,
        "file": path.name,
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def remove_signing_detritus(root: Path) -> None:
    for name in SIGNING_DETRITUS_XATTRS:
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
    remaining = [name for name in SIGNING_DETRITUS_XATTRS if f"{name}:" in result.stdout]
    if remaining:
        raise ValueError(
            "release app contains Finder metadata rejected by codesign: "
            + ", ".join(remaining)
        )


def main() -> None:
    args = parse_args()
    app = within_repo(args.app, strict=True)
    output = within_repo(args.output, strict=False)
    app_name = args.app_name.strip()

    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("--app must be an existing .app directory")
    if not app_name or "/" in app_name or ":" in app_name:
        raise ValueError("--app-name must be a non-empty macOS file-safe name")
    if output.exists():
        raise FileExistsError(f"refusing to overwrite release directory: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)

    info_path = app / "Contents" / "Info.plist"
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("CFBundleDisplayName") != app_name or info.get("CFBundleName") != app_name:
        raise ValueError("app bundle name does not match --app-name")
    if info.get("CFBundleShortVersionString") != args.version:
        raise ValueError("app bundle version does not match --version")
    if info.get("LSMinimumSystemVersion") != "14.0":
        raise ValueError("public app must require macOS 14.0")

    binary = app / "Contents" / "MacOS" / "petsgraph"
    architectures = subprocess.run(
        ["/usr/bin/lipo", "-archs", str(binary)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if architectures != "arm64":
        raise ValueError(f"public app must be Apple Silicon only, got: {architectures}")
    sanitized_root = Path(tempfile.mkdtemp(prefix="petsgraph-release-app-"))
    sanitized_app = sanitized_root / app.name
    build_output = Path(
        tempfile.mkdtemp(prefix=f"{output.name}.build-", dir=output.parent)
    )
    try:
        shutil.copytree(app, sanitized_app, copy_function=shutil.copy2)
        remove_signing_detritus(sanitized_app)
        assert_no_signing_detritus(sanitized_app)
        subprocess.run(
            [
                "/usr/bin/codesign",
                "--verify",
                "--deep",
                "--strict",
                "--verbose=2",
                str(sanitized_app),
            ],
            check=True,
        )
        package_metadata = read_embedded_pet_metadata(sanitized_app)
        pet_names = "、".join(
            str(pet["displayName"])
            for pet in package_metadata["embeddedPets"]
        )
        prefix = f"PetsGraph-v{args.version}-macOS-arm64"
        dmg = build_output / f"{prefix}.dmg"

        dmg_stage = Path(tempfile.mkdtemp(prefix="petsgraph-release-dmg-"))
        try:
            shutil.copytree(
                sanitized_app,
                dmg_stage / f"{app_name}.app",
                copy_function=shutil.copy2,
            )
            (dmg_stage / "Applications").symlink_to("/Applications")
            (dmg_stage / "安装说明.txt").write_text(
                f"""PetsGraph 安装说明

1. 把“{app_name}.app”拖到 Applications 文件夹。
2. 第一次打开时，在 Finder 中右键点击 App，选择“打开”，再确认一次“打开”。
3. 如果系统仍然阻止运行，请到“系统设置 > 隐私与安全性”，确认打开 {app_name}。
4. App 启动后，点击菜单栏里的爪印，可以指定宠物睡姿或退出。

当前内置宠物：{pet_names}。
以后安装其他宠物包时，App 名称仍保持 {app_name}。

支持 macOS 14 及以上版本，仅支持 Apple 芯片 Mac。
当前公开测试版使用 ad-hoc 签名，尚未经过 Apple 公证，因此首次打开会出现系统安全提示。
运行时完全离线，不需要账号，不上传数据。
""",
                encoding="utf-8",
            )
            assets_notice = ROOT / "ASSETS.md"
            if assets_notice.is_file():
                shutil.copy2(assets_notice, dmg_stage / "素材使用说明.md")
            subprocess.run(
                [
                    "/usr/bin/hdiutil",
                    "create",
                    "-volname",
                    app_name,
                    "-srcfolder",
                    str(dmg_stage),
                    "-ov",
                    "-format",
                    "UDZO",
                    str(dmg),
                ],
                check=True,
            )
        finally:
            shutil.rmtree(dmg_stage, ignore_errors=True)

        artifacts: list[tuple[Path, str]] = [(dmg, "installer-dmg")]
        subprocess.run(["/usr/bin/hdiutil", "verify", str(dmg)], check=True)

        entries = [artifact_entry(path, kind) for path, kind in artifacts]
        metadata = {
            "schema": 1,
            "tag": f"v{args.version}",
            "version": args.version,
            "platform": "macos-arm64",
            "minimumSystemVersion": "14.0",
            **package_metadata,
            "artifacts": entries,
        }
        (build_output / "artifact-metadata.json").write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        build_output.rename(output)
    except Exception:
        shutil.rmtree(build_output, ignore_errors=True)
        raise
    finally:
        shutil.rmtree(sanitized_root, ignore_errors=True)
    print(json.dumps(metadata, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
