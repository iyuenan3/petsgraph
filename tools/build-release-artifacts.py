#!/usr/bin/env python3
"""Build distributable archives for one versioned Wubai companion app."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--preview", type=Path)
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


def main() -> None:
    args = parse_args()
    app = within_repo(args.app, strict=True)
    package = within_repo(args.package, strict=True)
    preview = within_repo(args.preview, strict=True) if args.preview else None
    output = within_repo(args.output, strict=False)

    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("--app must be an existing .app directory")
    if not package.is_dir() or package.suffix != ".petsgraph-pet":
        raise ValueError("--package must be an existing .petsgraph-pet directory")
    if output.exists():
        raise FileExistsError(f"refusing to overwrite release directory: {output}")
    output.mkdir(parents=True)

    prefix = f"PetsGraph-Wubai-Quiet-Companion-v{args.version}"
    app_zip = output / f"{prefix}-macOS.zip"
    package_zip = output / f"wubai-quiet-companion-v{args.version}.petsgraph-pet.zip"
    dmg = output / f"{prefix}-macOS.dmg"

    subprocess.run(
        ["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(app_zip)],
        check=True,
    )
    subprocess.run(
        [
            "/usr/bin/ditto",
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            str(package),
            str(package_zip),
        ],
        check=True,
    )

    temporary = Path(tempfile.mkdtemp(prefix="petsgraph-release-dmg-"))
    try:
        shutil.copytree(app, temporary / "李五百睡觉陪伴.app", copy_function=shutil.copy2)
        (temporary / "Applications").symlink_to("/Applications")
        (temporary / "安装说明.txt").write_text(
            """李五百睡觉陪伴安装说明

1. 把“李五百睡觉陪伴.app”拖到右侧的 Applications 文件夹。
2. 第一次打开时，在 Finder 中右键点击 App，选择“打开”，再确认一次“打开”。
3. 如果系统仍然阻止运行，请到“系统设置 > 隐私与安全性”，确认打开李五百睡觉陪伴。
4. App 启动后，点击菜单栏里的爪印，可以指定五百的睡姿或退出。

支持 macOS 14 及以上版本，仅支持 Apple 芯片 Mac。
当前公开测试版使用 ad-hoc 签名，尚未经过 Apple 公证，因此首次打开会出现系统安全提示。
运行时完全离线，不需要账号，不上传数据。
""",
            encoding="utf-8",
        )
        assets_notice = ROOT / "ASSETS.md"
        if assets_notice.is_file():
            shutil.copy2(assets_notice, temporary / "素材使用说明.md")
        subprocess.run(
            [
                "/usr/bin/hdiutil",
                "create",
                "-volname",
                "李五百睡觉陪伴",
                "-srcfolder",
                str(temporary),
                "-ov",
                "-format",
                "UDZO",
                str(dmg),
            ],
            check=True,
        )
    finally:
        shutil.rmtree(temporary, ignore_errors=True)

    artifacts = [dmg, app_zip, package_zip]
    if preview is not None:
        preview_output = output / f"Wubai-Sleep-Postures-v{args.version}.png"
        shutil.copy2(preview, preview_output)
        artifacts.append(preview_output)

    subprocess.run(["/usr/bin/unzip", "-tq", str(app_zip)], check=True)
    subprocess.run(["/usr/bin/unzip", "-tq", str(package_zip)], check=True)
    subprocess.run(["/usr/bin/hdiutil", "verify", str(dmg)], check=True)

    entries = [
        {"file": artifact.name, "bytes": artifact.stat().st_size, "sha256": sha256(artifact)}
        for artifact in artifacts
    ]
    checksums = output / "SHA256SUMS.txt"
    checksums.write_text(
        "".join(f"{entry['sha256']}  {entry['file']}\n" for entry in entries),
        encoding="utf-8",
    )
    entries.append(
        {"file": checksums.name, "bytes": checksums.stat().st_size, "sha256": sha256(checksums)}
    )
    metadata = {
        "schema": 1,
        "version": args.version,
        "artifacts": entries,
    }
    (output / "artifact-metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(metadata, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
