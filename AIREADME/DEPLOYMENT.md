# DEPLOYMENT：petsgraph

## 主机 + 环境

PetsGraph `0.4.0` 构建为 Apple 芯片专用 App、DMG 和 ZIP，当前内嵌宠物为李五百。内嵌素材包使用 schema `0.4.0` 与 `cropped-rgba-clips`，状态为 `runtime-chain-approved` 与 `installable=true`。公开版最低支持 macOS 14，不构建 Intel 或通用二进制。

当前生产验证环境：Apple 芯片 macOS、Xcode 26.6 完整版、Swift 6.3.3、Python 3.12 和 Pillow 12.2.0。当前 `xcode-select` 指向的 CommandLineTools 不包含 `Testing` 或 `XCTest` 模块，裸跑 `swift test` 不是可信基线。测试脚本显式使用 `/Applications/Xcode.app/Contents/Developer`，不修改全局 `xcode-select`。v0.4.0 真实执行 57 项 XCTest，0 失败。

## 朋友安装

公开入口：<https://github.com/iyuenan3/petsgraph/releases/tag/v0.4.0>

推荐下载 `PetsGraph-v0.4.0-macOS-arm64.dmg`：

1. 打开 DMG。
2. 把 `PetsGraph.app` 拖入「应用程序」。
3. 第一次启动时，如果 macOS 阻止打开，在 Finder 中右键 App 并选择「打开」。也可以前往「系统设置 > 隐私与安全性」确认打开。

当前 App 使用 ad-hoc 签名，没有 Developer ID 签名和 Apple 公证。必须在下载页和安装说明中保留这个边界，不能把手动确认包装成无提示安装。

## 公开 Release 附件

| 附件 | 用途 |
|---|---|
| `PetsGraph-v0.4.0-macOS-arm64.dmg` | 普通用户推荐安装入口 |
| `PetsGraph-v0.4.0-macOS-arm64.zip` | 备用 App 下载 |
| `Wubai-Sleep-Postures-v0.4.0.png` | 十种睡姿总览 |
| `SHA256SUMS.txt` | 附件完整性校验 |

附件的固定字节数和 SHA-256 记录在 `release/manifests/v0.4.0.json`。Release 不重复上传已经内嵌在 App 中的 `.petsgraph-pet`。正式媒体属于 Release 附件，不提交到 Git 历史。源照片、生成母片、Seedance 任务记录、被拒绝候选和私有生产配置不公开。

## 开发和生产构建

公开代码测试：

```bash
bash tools/test-swift.sh
```

私有素材包编译需要 Pillow，使用隔离环境，不修改 Homebrew 或系统 Python：

```bash
uv venv .venv --python /opt/homebrew/bin/python3.12
uv pip install --python .venv/bin/python -r requirements-prototype.txt
.venv/bin/python tools/build-prototype-package.py \
  --config workspaces/wubai-private/runtime-records/wubai-quiet-companion-0.3.1-source.json \
  --output workspaces/wubai-private/runtime/wubai-quiet-companion-0.3.1.petsgraph-pet
```

从冻结 PNG 包构建正式低功耗包，不覆盖源包：

```bash
.venv/bin/python tools/build-cropped-rgba-package.py \
  --source-package workspaces/wubai-private/runtime/wubai-quiet-companion-0.3.1.petsgraph-pet \
  --output workspaces/wubai-private/runtime/wubai-quiet-companion-0.4.0.petsgraph-pet \
  --version 0.4.0 \
  --release-approved
```

`--release-approved` 只允许来源包已经是 `runtime-chain-approved` 与 `installable=true`，且版本是正式语义版本。没有该参数时，构建器强制输出 `cropped-rgba-awaiting-human-runtime-review` 与 `installable=false`。两种路径都逐 clip 使用一个固定 alpha 并集裁剪，重建 `source-assets.json` 与 `integrity.json`，不修改 v0.3.1 PNG 源包。

校验正式包结构、行为图和全部运行时媒体：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=.build/ModuleCache-Xcode \
SWIFTPM_MODULECACHE_OVERRIDE=.build/ModuleCache-Xcode \
  xcrun swift run --disable-sandbox petsgraph \
  workspaces/wubai-private/runtime/wubai-quiet-companion-0.4.0.petsgraph-pet \
  --validate-only

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=.build/ModuleCache-Xcode \
SWIFTPM_MODULECACHE_OVERRIDE=.build/ModuleCache-Xcode \
  xcrun swift run --disable-sandbox petsgraph \
  workspaces/wubai-private/runtime/wubai-quiet-companion-0.4.0.petsgraph-pet \
  --validate-media
```

构建 Apple 芯片 App：

```bash
.venv/bin/python tools/build-macos-app.py \
  --package workspaces/wubai-private/runtime/wubai-quiet-companion-0.4.0.petsgraph-pet \
  --output workspaces/wubai-private/runtime/PetsGraph-0.4.0.app \
  --version 0.4.0 \
  --build-number 4
```

构建公开附件：

```bash
.venv/bin/python tools/build-release-artifacts.py \
  --app workspaces/wubai-private/runtime/PetsGraph-0.4.0.app \
  --version 0.4.0 \
  --output workspaces/wubai-private/release-dist/v0.4.0 \
  --preview workspaces/wubai-private/release-dist/v0.3.1/Wubai-Sleep-Postures-v0.3.1.png
```

DMG 使用本机 `/usr/bin/hdiutil create` 构建，GitHub Actions 不重新编译附件。构建器必须执行 ZIP 解包校验和 `hdiutil verify`，并拒绝 App 与内嵌宠物包版本不一致、非 `runtime-chain-approved` 或 `installable=false` 的输入。App 主可执行文件的 `lipo -archs` 结果必须严格等于 `arm64`。

## GitHub 发布流程

1. 先提交并推送实现、发布清单和文档。
2. 在最终文档提交上创建带注释的语义版本标签，例如 `v0.4.0`。
3. 使用 `docs/releases/v0.4.0.md` 和清单声明的四个附件创建草稿 Release。
4. 手动触发 `.github/workflows/release.yml`，传入同一个标签。
5. Actions 检出精确标签，运行 57 项测试，下载所有草稿附件并验证文件名、字节数、SHA-256、schema `0.4.0`、`cropped-rgba-clips`、批准状态和 arm64 架构。
6. 只有全部校验通过，工作流才把草稿改成正式最新版。
7. 发布后回读 Release 的草稿状态、标签、附件名和附件大小，并测试公开下载入口。

任何一步失败都保留草稿，不自动重新上传、不重打同名标签，也不把未核验附件暴露为正式版。

## 运行时与隐私

- App 默认把宠物地面锚点放在物理屏幕左下角。
- 用户可以在整个桌面改变 x 和 y；睡眠行为不会改写用户放置的 y。
- 菜单栏「选择睡姿」只显示中文名称。指定姿态沿同一动作图、安全退出和预加载链执行。
- 正式模式不开放点击目的地移动、走跑工程菜单或全桌面点击监听。
- 睡眠 MVP 不需要账号、登录、辅助功能权限、屏幕录制权限或全局鼠标监听。
- 运行时不读取 provider 凭据，不联网生成，不上传宠物照片，不发送遥测。
- 锁屏和系统睡眠时暂停窗口与动画时钟，恢复后回到稳定姿态。
- 正式 GUI 运行使用每用户单实例锁，第二次启动在加载宠物包前退出。校验命令可以与 GUI 同时运行。
- 性能采样前用 PID 和完整命令路径确认只存在一个当前版本。旧 AppTranslocation 进程可能在 Gatekeeper 延迟放行后出现，必须单独终止并记录，不能把旧版本资源归因给当前包。

## 备份、升级与回滚

- 原始照片和视频母片由素材所有者在私有制作工作区备份。
- 每个公开版本使用独立标签、Release、清单和附件名，不覆盖上一版本。
- 新包失败时保留当前可用版本。schema 不兼容时拒绝导入。
- 回滚时从上一条正式 Release 重新安装，并使用对应 `SHA256SUMS.txt` 核验。
- 同名标签或附件校验不一致时停止发布，不修改已有正式 Release 来掩盖差异。

## 运维约束

- 运行时不得联网生成或上传宠物素材。
- 不因 provider 超时、失败或本地网络错误自动重复付费调用。
- 未通过 `runtime-chain-approved` 的包只能进入显式预览模式，不能替换正式宠物。
- `cropped-rgba-awaiting-human-runtime-review` 候选不得进入公开 Release。正式低功耗包还必须来自已批准 PNG 包、获得明确版本发布授权，并由发布工作流再次核对 schema、渲染模式、批准状态和 `installable=true`。
- 图规划、解码或预加载错误时回到兼容稳定睡姿并记录错误，不能直接让应用消失。
- 默认运行不得注册全局桌面点击 monitor。
- Developer ID 签名和 Apple 公证完成前，所有公开页面都必须说明首次打开的系统确认步骤。
