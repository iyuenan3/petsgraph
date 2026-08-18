# DEPLOYMENT：petsgraph

## macOS v0.5.10 发布基线

PetsGraph `0.5.10` 是 Apple 芯片专用双宠正式版，最低支持 macOS 14。App 名称为 `PetsGraph`，Bundle ID 为 `com.maxwell.petsgraph`，使用 ad-hoc 签名，尚未使用 Developer ID 或 Apple 公证。

| 宠物 | 内嵌包 | clip | 帧 | `baseHeightPt` | 状态 |
|---|---|---:|---:|---:|---|
| 五百 | `wubai-quiet-companion-0.5.10` | 53 | 6,866 | 172.5 | `runtime-chain-approved`、`installable=true` |
| 飞流 | `feiliu-quiet-companion-0.5.10` | 31 | 5,147 | 181.125 | `runtime-chain-approved`、`installable=true` |

两包均使用 schema `0.4.0` 与 `cropped-rgba-clips`。飞流在 1.0× 下比五百大 5%。历史正式构建路径为 `dist/PetsGraph-0.5.10.app`，本地 Release 产物为 `workspaces/release-dist/v0.5.10/PetsGraph-v0.5.10-macOS-arm64.dmg`。v0.5.10 发布完成后，用户已授权清理 `dist/` 中的旧 macOS App 与候选产物，当前回滚事实以 Git 标签、GitHub Release、仓库清单和私有批准包为准。

DMG 固定属性：

- 字节数：`856000287`
- SHA-256：`460395f97c46899eea13947fa8606fc9271f6a02e1171cb3281d98a37cf2bca6`
- 主可执行架构：严格为 `arm64`
- Release 附件：精确一个 DMG

公开 Release 不提供 App ZIP、预览图、校验和附件或独立 `.petsgraph-pet`。附件哈希记录在 `release/manifests/v0.5.10.json`。

## Windows v0.6.0 发布基线

Windows `0.6.0` 只面向 Windows 11 x64 与知情的内部朋友。它使用 .NET 10 WPF，以 self-contained 多文件便携 ZIP 交付，不需要用户预装 .NET。当前不构建 MSIX、安装器或代码签名。

冻结发布产物：

- 路径：`dist/PetsGraph-v0.6.0-Windows-x64.zip`
- 字节数：`913953281`
- SHA-256：`90578d6620ef9c221c173b173c24631d6e756b372b532030f8669994d22b0015`
- ZIP 条目：`488`
- 内嵌宠物包：`2`，五百与飞流
- 主程序：PE32+ GUI，x86-64

该 ZIP 已在 macOS arm64 本机使用 .NET SDK `10.0.400` 交叉发布，并通过压缩数据、无 `__MACOSX`/`.DS_Store`、双包数量和真实包完整性校验。7 项 MSTest、WPF 编译、GitHub Windows Runner 与朋友真实 Windows 11 x64 使用验收均已通过，朋友反馈没有问题，发布所有者明确授权发布 v0.6.0。真机反馈没有附带分项时长或 DPI 日志，因此只记录最终结论。`dist/` 已删除约 34 GB 的旧 macOS 候选 App 和 4 份废弃 Windows ZIP，当前只保留这一份冻结 ZIP。

## macOS 用户安装

公开入口：<https://github.com/iyuenan3/petsgraph/releases/tag/v0.5.10>

1. 下载 `PetsGraph-v0.5.10-macOS-arm64.dmg`。
2. 打开 DMG，把 `PetsGraph.app` 拖入“应用程序”。
3. 首次启动如被 macOS 阻止，在 Finder 中右键 App 选择“打开”，或在“系统设置 → 隐私与安全性”中确认。
4. 首次安装默认同时装载五百和飞流，并在屏幕左下角横排。

App 离线运行，不上传照片，不访问生成服务，不收集遥测，也不要求辅助功能权限。

## Windows 安装

公开入口：<https://github.com/iyuenan3/petsgraph/releases/tag/v0.6.0>

1. 从 GitHub Release 下载 `PetsGraph-v0.6.0-Windows-x64.zip`，需要时先核对 SHA-256。
2. 解压完整 ZIP，不要只把 `PetsGraph.exe` 拖到其他目录。`PetsGraph.exe`、.NET 运行文件和 `Pets` 必须保持在同一解压目录中。
3. 双击 `PetsGraph.exe`。未签名版本可能触发 SmartScreen，只在文件来源和哈希已核对时继续。
4. 右键系统托盘中的双猫图标，可以分别显示、隐藏宠物、选择睡姿、设置全局大小或退出。
5. 设置保存到 `%LOCALAPPDATA%\PetsGraph\settings.json`。当前版本不写注册表、不安装系统服务，也不配置开机自启。

## macOS 本机构建与验证

测试必须使用完整 Xcode 基线：

```bash
bash tools/test-swift.sh
```

构建正式 App：

```bash
python3 tools/build-macos-app.py \
  --package workspaces/wubai-private/runtime/wubai-quiet-companion-0.5.10.petsgraph-pet \
  --package workspaces/feiliu-private/runtime/feiliu-quiet-companion-0.5.10.petsgraph-pet \
  --output dist/PetsGraph-0.5.10.app \
  --version 0.5.10 \
  --min-macos 14.0
```

构建唯一发布附件：

```bash
python3 tools/build-release-artifacts.py \
  --app dist/PetsGraph-0.5.10.app \
  --output workspaces/release-dist/v0.5.10 \
  --version 0.5.10
```

正式构建必须通过：

- 67 项 XCTest。
- 两个包的 schema、版本、批准状态、图、完整性和全部 12,013 帧媒体校验。
- App 主可执行文件 `arm64` 架构检查。
- `codesign --verify --deep --strict`。
- `hdiutil verify`，挂载后再次检查 App、签名、版本和两个内嵌包。
- 发布目录精确只有一个 DMG，字节数和 SHA-256 与仓库清单一致。

DMG 使用本机 `/usr/bin/hdiutil create` 从冻结 App 构建。GitHub Actions 不重新编译媒体或 App，只验证并发布这份已验收附件。本机受限沙箱可能让 `hdiutil` 报“设备未配置”，此时必须确认没有残留半成品，再以明确的磁盘映像权限重跑同一确定性命令。

## Windows 构建与验证

仓库用 `global.json` 锁定 .NET SDK `10.0.400`。macOS arm64 本机 SDK 安装在 `~/.dotnet`，未修改用户全局 PATH。核心命令：

```bash
DOTNET_CLI_HOME=/private/tmp/petsgraph-dotnet-home \
  ~/.dotnet/dotnet test windows/tests/PetsGraph.Core.Tests/PetsGraph.Core.Tests.csproj \
  --no-restore --disable-build-servers -m:1 -p:UseSharedCompilation=false

DOTNET_CLI_HOME=/private/tmp/petsgraph-dotnet-home \
  ~/.dotnet/dotnet build windows/PetsGraph.slnx \
  --no-restore --disable-build-servers -m:1 \
  -p:UseSharedCompilation=false -p:RestoreLockedMode=true

PETSGRAPH_PETS_DIR=dist/PetsGraph-0.5.10.app/Contents/Resources/Pets \
DOTNET_BIN=~/.dotnet/dotnet \
DOTNET_CLI_HOME=/private/tmp/petsgraph-dotnet-home \
  bash windows/scripts/build-portable.sh
```

`build-portable.sh` 拒绝覆盖同名 ZIP，先交叉发布 `win-x64` self-contained 应用，再用 .NET 校验器检查真实宠物包，复制完整包后生成 ZIP，最后执行解压测试与 SHA-256。发布前还必须检查：

- 7 项 MSTest，覆盖 RGBA 到 PBGRA 转换、鼠标 alpha、点击往返、左右 root motion、时间线和方形视口。
- WPF 与全解决方案零警告、零错误编译。
- 五百 53 clip、飞流 31 clip，共 12,013 帧的结构、批准状态、媒体长度、首尾帧渲染和 SHA-256 完整性。
- ZIP 可完整解压，主程序为 AMD64 PE32+ GUI，包含两个 `.petsgraph-pet`，不包含 macOS 元数据。
- 真实 Windows 11 x64 上的透明、DPI、命中、拖动、托盘、边界、锁屏恢复和长时运行人工闸门。

GitHub 推送到 `codex/windows-win11-x64`、`main` 或相关 Pull Request 时，`.github/workflows/windows.yml` 在 `windows-2025` 上重新执行锁定还原、测试、WPF 编译、代码运行 ZIP、AMD64 PE 和 ZIP 结构检查。该 artifact 不含私有宠物媒体，仅保留 7 天。内容提交 `2b539a6` 对应运行 `32114691048`，全部步骤通过。

`.github/workflows/windows-release-verify.yml` 只验证已上传到草稿 Release 的 Windows ZIP，它不创建标签、不上传附件、不发布草稿。GitHub 会对只有 `contents: read` 的工作流 token 隐藏草稿 Release，因此该工作流经发布所有者明确授权使用 `contents: write`，但步骤只允许 `gh release view` 与 `gh release download`。流程从默认分支读取当前工作流定义，再检出精确标签，要求草稿附件集合与清单严格一致，并核对字节数、SHA-256、版本、AMD64 PE、双包数量和运行时完整性。

## macOS GitHub 公开发布流程

1. 先提交实现并执行测试、包校验、App 校验和 DMG 校验。
2. 以实现提交更新 README、AIREADME、Release 说明和固定清单，单独提交文档。
3. 在文档提交上创建带注释标签 `v0.5.10`，推送 `main` 与标签。
4. 使用 `docs/releases/v0.5.10.md` 创建草稿 Release，只上传清单指定的 DMG。
5. 手动触发 `.github/workflows/release.yml`，输入标签 `v0.5.10`。
6. GitHub Actions 检出精确标签，执行测试、下载并校验草稿附件、挂载 DMG、检查 arm64、签名、版本、双宠包和媒体，再发布草稿。
7. 发布后回读 Release，确认不是草稿、不是预发布、附件数量严格为一、名称、字节数和摘要匹配清单。

任何附件、标签或提交不一致都必须停止发布。不能原位移动已有正式标签，也不能用另一次远端编译替代本机人工验收过的 DMG。

## Windows GitHub 发布流程

1. 冻结真实 Windows 11 x64 验收过的 ZIP，记录精确名称、字节数和 SHA-256，不重新编译另一份附件。
2. 提交 README、`docs/releases/v0.6.0.md`、`release/manifests/v0.6.0.json` 和 Windows 草稿验证工作流，再以该内容提交为锚点更新 AIREADME。
3. 在最终文档提交上创建带注释标签 `v0.6.0`，推送当前发布分支与标签。
4. 使用 `docs/releases/v0.6.0.md` 创建草稿 Release，精确只上传清单指定的 Windows ZIP。
5. 从默认分支手动触发 `.github/workflows/windows-release-verify.yml`，输入标签 `v0.6.0`。工作流定义来自默认分支，校验对象由 checkout 显式固定到不可移动的发布标签。
6. Windows Runner 检出精确标签，从草稿 Release 下载冻结 ZIP，并按仓库清单完成全部复验。只有该运行成功后，才能把草稿发布为最新版。
7. 发布后回读 Release，确认不是草稿、不是预发布、附件数量严格为一，名称、字节数、摘要、标签提交和工作流运行均与冻结基线一致。

v0.6.0 不触发只适用于 macOS DMG 的 `.github/workflows/release.yml`。上传过程如果长时间无输出，先继续轮询原进程或回读远端附件状态，不重复上传，不使用 `--clobber` 覆盖未知状态的正式附件。

## 回滚与运维

- 历史标签、Release、五百 PNG 基线和飞流制作事实源保留，不覆盖或删除。
- 正式媒体不进入 Git 历史，只保留小型清单、构建器与验证逻辑。
- 重复启动由每用户进程锁在加载大媒体前退出，避免出现两个 PetsGraph 进程。
- App 只使用一个共享 24 Hz 渲染 Timer，每只宠物仍拥有独立行为会话和随机时钟。
- 双宠长期 CPU 与内存继续收集真实数据。性能结论必须注明唯一 PID、测量工具、稳定睡眠或过渡场景，不能把旧 AppTranslocation 进程计入当前版本。
- 下一版如改变素材、位置、体型、窗口命中、动作图或发布附件，必须重跑相应自动检查和真实桌面人工闸门。
- Windows 历史候选 ZIP 已从 `dist/` 清理，不用旧哈希冒充最新产物。后续重建必须使用新版本名并重新记录字节数和 SHA-256，已上传的正式附件不原位覆盖。
