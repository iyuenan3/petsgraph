# DEPLOYMENT：petsgraph

## 状态与下一代分发目标

当前可下载的 `v0.6.0` 仍是内嵌五百与飞流的历史正式版，下面的构建、安装、摘要和双平台发布流程继续作为该版本的事实与回滚依据。零素材 PetsGraph Player、外部 `.petpack` 装载和内部宠物库尚未实现，不能用目标文档替换当前安装说明。

下一代发布边界：

- Apple Silicon macOS 与 Windows x64 Player 分别发布，但两个安装包都不包含真实宠物素材。
- Player 源码、PetPack 规范、验证器、合成测试资产和发布流程公开。
- Seedance 等制作工具、客户目录、未公开母片和未来正式 PetPack 保持私有，不进入公开 Player 发布物。五百与飞流已经公开的历史素材继续按 `ASSETS.md` 保留，不再内嵌到下一代 Player。
- 用户从 Maxwell 获得 `.petpack` 后自行长期保存，通过 Player 的“装载宠物包…”导入内部 canonical 库。
- Player 二进制、canonical 宠物库与可重建 cache 分目录保存。升级只能替换应用和可重建 cache，不能修改或删除已装载宠物。
- 普通卸载 Player 默认保留内部宠物库；彻底删除用户数据必须单独确认。卸载某只宠物则删除内部包及其本地状态，之后需要原始 `.petpack` 才能恢复。
- 当前不构建 iPadOS、电视端、Intel Mac、Windows on Arm 或 32 位 Windows，但 PetPack 1.0 不能包含桌面窗口、平台路径或特定 OS 行为。

下一代应用继续使用名称 `PetsGraph`，macOS 保留 Bundle ID `com.maxwell.petsgraph`，Windows 保留 `PetsGraph` 应用身份。macOS 数据根为 `~/Library/Application Support/PetsGraph/`，Windows 数据根为 `%LOCALAPPDATA%\PetsGraph\`；其中 `library/` 保存 canonical PetPack，`cache/` 可重建，`settings/` 保存 Player 与每宠状态。开发阶段版本使用 `0.7.0-dev`，五百、飞流和双平台 Player 通过后发布 `1.0.0`。

PetPack 1.0 使用普通 ZIP 容器和必需的 `cropped-rgba-clips` 基础表示。五百与飞流首批包只有完整性哈希，不带官方签名；签名、公证、Windows 代码签名和可选紧凑媒体均属于后续增强。历史 `v0.6.0` 路径和摘要不因新方向而改写。

## macOS v0.6.0 发布基线

PetsGraph `0.6.0` 是 Apple 芯片专用双宠正式版，最低支持 macOS 14。App 名称为 `PetsGraph`，Bundle ID 为 `com.maxwell.petsgraph`，使用 ad-hoc 签名，尚未使用 Developer ID 或 Apple 公证。App 使用新的双猫相伴 Logo，继续内嵌已经验收的两个 `0.5.10` 宠物包。

| 宠物 | 内嵌包 | clip | 帧 | `baseHeightPt` | 状态 |
|---|---|---:|---:|---:|---|
| 五百 | `wubai-quiet-companion-0.5.10` | 53 | 6,866 | 172.5 | `runtime-chain-approved`、`installable=true` |
| 飞流 | `feiliu-quiet-companion-0.5.10` | 31 | 5,147 | 181.125 | `runtime-chain-approved`、`installable=true` |

两包均使用 schema `0.4.0` 与 `cropped-rgba-clips`。飞流在 1.0× 下比五百大 5%。v0.6.0 构建路径为 `dist/PetsGraph-0.6.0.app`，本地 Release 产物为 `workspaces/release-dist/v0.6.0/PetsGraph-v0.6.0-macOS-arm64.dmg`。App 版本与宠物内容版本分别记录，不为 Logo 更新重新编译或改写 12,013 帧已批准媒体。

DMG 固定属性：

- 字节数：`857640594`
- SHA-256：`04c6f30e35d7dd8b5b096d0051aad628987d59b8245d84060cf704f02709b159`
- 主可执行架构：严格为 `arm64`
- 内嵌 ICNS SHA-256：`8b976a2ebe6badbcd6709201a03dc5900ed45c7bad01d4a210fde8cdbf38c24d`

v0.6.0 Release 共有两个附件，一个 macOS DMG 和一个 Windows ZIP。它不提供 App ZIP、预览图、校验和附件或独立 `.petsgraph-pet`。两个附件哈希记录在 `release/manifests/v0.6.0.json`。

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

公开入口：<https://github.com/iyuenan3/petsgraph/releases/tag/v0.6.0>

1. 下载 `PetsGraph-v0.6.0-macOS-arm64.dmg`。
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
bash player/macos/scripts/test.sh
```

构建正式 App：

```bash
.venv/bin/python player/macos/scripts/build-legacy-app.py \
  --package workspaces/wubai-private/runtime/wubai-quiet-companion-0.5.10.petsgraph-pet \
  --package workspaces/feiliu-private/runtime/feiliu-quiet-companion-0.5.10.petsgraph-pet \
  --output dist/PetsGraph-0.6.0.app \
  --version 0.6.0
```

构建唯一发布附件：

```bash
.venv/bin/python studio/packaging/build-release-artifacts.py \
  --app dist/PetsGraph-0.6.0.app \
  --output workspaces/release-dist/v0.6.0 \
  --version 0.6.0
```

正式构建必须通过：

- 67 项 XCTest。
- 两个包的 schema、独立包版本、批准状态、图、完整性和全部 12,013 帧媒体校验。
- App 主可执行文件 `arm64` 架构检查。
- `codesign --verify --deep --strict`。
- `hdiutil verify`，只读挂载后再次检查 App、签名、版本、ICNS 哈希和两个内嵌包。
- 发布目录精确只有一个 DMG，本地字节数和 SHA-256 与双平台仓库清单中的 macOS 条目一致。

DMG 使用本机 `/usr/bin/hdiutil create` 从冻结 App 构建。GitHub Actions 不重新编译媒体或 App。公开后的 macOS 工作流只使用 `contents: read` 下载、校验和挂载已发布附件，不具备发布权限。本机受限沙箱可能让 `hdiutil` 报“设备未配置”，此时必须确认没有残留半成品，再以明确的磁盘映像权限重跑同一确定性命令。

## Windows 构建与验证

仓库用 `player/windows/global.json` 锁定 .NET SDK `10.0.400`。macOS arm64 本机 SDK 安装在 `~/.dotnet`，未修改用户全局 PATH。核心命令：

```bash
DOTNET_CLI_HOME=/private/tmp/petsgraph-dotnet-home \
  ~/.dotnet/dotnet test player/windows/tests/PetsGraph.Core.Tests/PetsGraph.Core.Tests.csproj \
  --no-restore --disable-build-servers -m:1 -p:UseSharedCompilation=false

DOTNET_CLI_HOME=/private/tmp/petsgraph-dotnet-home \
  ~/.dotnet/dotnet build player/windows/PetsGraph.slnx \
  --no-restore --disable-build-servers -m:1 \
  -p:UseSharedCompilation=false -p:RestoreLockedMode=true

PETSGRAPH_PETS_DIR=/path/to/approved/Pets \
DOTNET_BIN=~/.dotnet/dotnet \
DOTNET_CLI_HOME=/private/tmp/petsgraph-dotnet-home \
  bash player/windows/scripts/build-portable.sh
```

`build-portable.sh` 拒绝覆盖同名 ZIP，先交叉发布 `win-x64` self-contained 应用，再用 .NET 校验器检查真实宠物包，复制完整包后生成 ZIP，最后执行解压测试与 SHA-256。发布前还必须检查：

- 7 项 MSTest，覆盖 RGBA 到 PBGRA 转换、鼠标 alpha、点击往返、左右 root motion、时间线和方形视口。
- WPF 与全解决方案零警告、零错误编译。
- 五百 53 clip、飞流 31 clip，共 12,013 帧的结构、批准状态、媒体长度、首尾帧渲染和 SHA-256 完整性。
- ZIP 可完整解压，主程序为 AMD64 PE32+ GUI，包含两个 `.petsgraph-pet`，不包含 macOS 元数据。
- 真实 Windows 11 x64 上的透明、DPI、命中、拖动、托盘、边界、锁屏恢复和长时运行人工闸门。

GitHub 推送到 `codex/windows-win11-x64`、`main` 或相关 Pull Request 时，`.github/workflows/windows.yml` 在 `windows-2025` 上重新执行锁定还原、测试、WPF 编译、代码运行 ZIP、AMD64 PE 和 ZIP 结构检查。该 artifact 不含私有宠物媒体，仅保留 7 天。内容提交 `2b539a6` 对应运行 `32114691048`，全部步骤通过。

`.github/workflows/windows-release-verify.yml` 只验证已上传到草稿 Release 的 Windows ZIP，它不创建标签、不上传附件、不发布草稿。GitHub 会对只有 `contents: read` 的工作流 token 隐藏草稿 Release，因此该工作流经发布所有者明确授权使用 `contents: write`，但步骤只允许 `gh release view` 与 `gh release download`。流程从默认分支读取双平台清单，确认不可移动标签是当前发布契约的祖先且 Windows 源码相对标签没有变化，要求草稿附件集合与清单严格一致，并核对字节数、SHA-256、版本、AMD64 PE、双包数量和运行时完整性。

两个 v0.6.0 Release 复验工作流保持发布时的旧路径与 tag 对 HEAD 完整源码差异门禁，本次目录迁移没有修改或削弱它们。提交 `84bbc5e` 之后的 `main` 不再把这两个历史工作流当作新 Player 的 CI；PetPack 1.0 与零素材 Player 必须建立独立的 1.0.0 构建和发布门禁。

## v0.6.0 GitHub 双平台发布流程

1. 冻结真实 Windows 11 x64 验收过的 ZIP 和本机只读挂载验证过的 macOS DMG，记录精确名称、字节数和 SHA-256。
2. 提交 README、`docs/releases/v0.6.0.md`、双平台 `release/manifests/v0.6.0.json`、打包器和两个验证工作流，再以该内容提交为锚点更新 AIREADME。
3. 保持带注释标签 `v0.6.0` 不移动。该标签固定指向 `ce4570cef6f47fe75b32df40c1476b0657a1d999`，其中已经包含两个平台宿主与双猫 Logo。默认分支上的发布补充必须验证平台源码相对标签无变化。
4. 使用 `docs/releases/v0.6.0.md` 维护草稿 Release，精确上传清单指定的 Windows ZIP 与 macOS DMG。上传过程长时间无输出时继续轮询原进程或回读远端状态，不重复上传，不使用 `--clobber` 覆盖未知状态附件。
5. 从默认分支触发 `.github/workflows/windows-release-verify.yml`。它经发布所有者明确授权使用 `contents: write` 读取草稿，但命令只允许查看和下载，复验双附件集合及 Windows ZIP 内容。
6. 本机维护者凭据回读草稿附件状态、字节数和摘要，并下载 macOS DMG 复核远端文件。两个冻结附件均确认后，单独把草稿发布为最新版。
7. 公开后从默认分支触发 `.github/workflows/release.yml`。它使用 `contents: read` 下载两个附件，核对字节数和摘要，只读挂载 DMG，并检查 App 版本、Logo、arm64、签名和双包完整性。
8. 最终回读 Release，确认不是草稿、不是预发布、附件数量严格为二，两个名称、字节数、摘要、标签提交和工作流运行均与冻结基线一致。

任何附件、标签或提交不一致都必须停止或撤回发布。不能原位移动已有正式标签，也不能用另一次远端编译替代本机人工验收过的附件。

v0.6.0 实际发布证据：Windows 草稿复验运行 `32139232230` 成功，公开 macOS 只读复验运行 `32139688614` 成功，两者均基于发布契约提交 `9c185fc`。远端最新版回读确认标签提交仍为 `ce4570cef6f47fe75b32df40c1476b0657a1d999`，两个附件均为 `uploaded`，Release 不是草稿也不是预发布。

## Codex 宠物导出维护与安装

本节命令记录当前 As-built。公开包、清单和管理工具已迁入 `codexpets/`，原路径不再提供兼容入口。目标结构与切换门禁见 `DIRECTORY.md`。

Codex 导出随普通 Git 分支分发，不增加 GitHub Release 附件。历史内容基线提交 `9f230c1` 使用 `codex-pets/`；当前目录迁移提交为 `76ad2ea`，包含 `codexpets/packages/public/`、`codexpets/manifests/public.json`、`codexpets/tools/manage.py` 和回归测试。

仓库维护者先运行：

```bash
python3 codexpets/tools/manage.py validate
```

该命令核对目录白名单、`pet.json` 字段、字节数、SHA-256、WebP 透明通道、1536×2288 尺寸和 8×11 网格契约。发布前还要分别使用 Hatch Pet `validate_atlas.py --require-v2` 复验两张图集，并在真实 Codex 窗口中观看动作与身份。

用户安装全部或单只宠物：

```bash
python3 codexpets/tools/manage.py install
python3 codexpets/tools/manage.py install wubai-v0
python3 codexpets/tools/manage.py install feiliu-hatch-native-v1
```

默认目标是 `${CODEX_HOME:-~/.codex}/pets/`。相同内容重复安装不写盘；不同内容必须由用户显式传入 `--force`，安装器先把旧目录移动到 `${CODEX_HOME:-~/.codex}/pets-backups/<UTC 时间>/`。安装后在 Codex 设置的 Pets 页面重新选择宠物，缓存未刷新时重启 Codex。

## 回滚与运维

- 历史标签、Release、五百 PNG 基线和飞流制作事实源保留，不覆盖或删除。
- 正式媒体不进入 Git 历史，只保留小型清单、构建器与验证逻辑。
- 重复启动由每用户进程锁在加载大媒体前退出，避免出现两个 PetsGraph 进程。
- App 只使用一个共享 24 Hz 渲染 Timer，每只宠物仍拥有独立行为会话和随机时钟。
- 双宠长期 CPU 与内存继续收集真实数据。性能结论必须注明唯一 PID、测量工具、稳定睡眠或过渡场景，不能把旧 AppTranslocation 进程计入当前版本。
- 下一版如改变素材、位置、体型、窗口命中、动作图或发布附件，必须重跑相应自动检查和真实桌面人工闸门。
- Windows 历史候选 ZIP 已从 `dist/` 清理，不用旧哈希冒充最新产物。后续重建必须使用新版本名并重新记录字节数和 SHA-256，已上传的正式附件不原位覆盖。
- v0.6.0 macOS App 完成发布后从 `dist/` 清理，正式 DMG 保留在 `workspaces/release-dist/v0.6.0/`，GitHub Release、双平台清单和已批准宠物包共同构成回滚事实。
- Codex 导出使用稳定 ID 和 Git 历史回滚。更新现有视觉内容时新建版本化 ID；强制本地替换留下 `pets-backups`，不物理删除旧目录。
