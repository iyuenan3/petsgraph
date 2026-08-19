# PetsGraph

<img src="assets/app-icon/petsgraph-logo.png" alt="PetsGraph 双猫相伴图标" width="128" height="128">

PetsGraph 是一个面向真实宠物的开源桌面陪伴运行时。当前提供 Apple 芯片 macOS 版和 Windows 11 x64 版，内置五百和飞流，让它们在你的桌面上安静睡觉、翻身，并偶尔换一个舒服的姿势。

[下载 Windows 11 x64 便携包](https://github.com/iyuenan3/petsgraph/releases/download/v0.6.0/PetsGraph-v0.6.0-Windows-x64.zip) · [下载 Apple 芯片 Mac 安装包](https://github.com/iyuenan3/petsgraph/releases/download/v0.6.0/PetsGraph-v0.6.0-macOS-arm64.dmg) · [查看 v0.6.0 发布说明](https://github.com/iyuenan3/petsgraph/releases/tag/v0.6.0)

## Windows 11 x64 便携版

Windows 版本采用 .NET 10 和 WPF，只提供免安装便携 ZIP，不制作 MSIX，也不做代码签名。它复用与 macOS 相同的 `schema 0.4.0` 双宠包、动作图、随机睡姿和完整性契约，并在 Windows 侧把预乘 RGBA 帧转换为 WPF 使用的 PBGRA32。

仓库包含 Windows 核心、WPF 主程序、测试、便携包脚本和 GitHub Windows Runner 工作流。交叉编译、双宠包真实加载、完整 SHA-256 校验和 x64 PE 校验已完成，朋友也已经在真实 Windows 11 x64 电脑上完成使用验收并反馈没有问题。GitHub Runner 与真机反馈是两层独立证据，本次真机反馈没有附带分项时长或 DPI 测试日志。

完整解压后直接运行 `PetsGraph.exe`，程序和 `Pets` 文件夹必须保持在同一目录。具体说明见 [`windows/README-Windows.md`](windows/README-Windows.md)。

## 下载与安装

### Windows 11 x64

1. 下载 [`PetsGraph-v0.6.0-Windows-x64.zip`](https://github.com/iyuenan3/petsgraph/releases/download/v0.6.0/PetsGraph-v0.6.0-Windows-x64.zip)。
2. 完整解压 ZIP，不要只把 `PetsGraph.exe` 拖到其他目录。
3. 双击 `PetsGraph.exe`。本版本没有代码签名，Windows 可能显示 SmartScreen 提示，请确认文件来自本项目 GitHub Release。
4. 如需核对完整性，文件 SHA-256 应为 `90578d6620ef9c221c173b173c24631d6e756b372b532030f8669994d22b0015`。

### Apple 芯片 macOS

macOS 版本需要 Apple 芯片和 macOS 14 或更高版本。v0.6.0 使用新的双猫相伴 Logo，继续内嵌已经验收的五百与飞流 `0.5.10` 宠物包。

1. 下载并打开 [`PetsGraph-v0.6.0-macOS-arm64.dmg`](https://github.com/iyuenan3/petsgraph/releases/download/v0.6.0/PetsGraph-v0.6.0-macOS-arm64.dmg)。
2. 把 `PetsGraph.app` 拖入 `Applications`。
3. 第一次启动时，如果 macOS 阻止打开，请在 Finder 中右键 App 并选择「打开」。也可以前往「系统设置 > 隐私与安全性」确认打开。

如需核对完整性，DMG 的 SHA-256 应为 `04c6f30e35d7dd8b5b096d0051aad628987d59b8245d84060cf704f02709b159`。

当前 App 使用 ad-hoc 签名，没有 Developer ID 签名和 Apple 公证，所以首次打开会出现安全提示。应用不需要联网，不上传照片，不连接素材生成服务，也不收集遥测数据。

## 当前内置宠物：五百和飞流

### 怎么陪它们

- 首次安装默认同时装载五百和飞流，五百在左、飞流在右，出现在屏幕左下角。
- 两只宠物各自维护独立的随机时钟、动作状态、拖动位置和睡姿，不会同步翻身。
- 点击睡眠中的宠物，它会沿自己的动作图醒来并正面坐好；再次点击会自然回去睡觉。
- 可以把每只宠物拖到桌面的任意位置，它们会保持在普通窗口和 Dock 前方。
- 菜单可以分别装载或卸载宠物，也可以为每只宠物直接指定中文睡姿。
- 全局大小提供 `0.5×` 到 `2.0×` 七档选择，并同时作用于全部宠物。
- 正在播放不可中断动作时，新的睡姿选择会排队，完成当前动作后自然切换，不会硬切画面。

十种可选睡姿：

- 普通睡姿：趴卧、左侧蜷卧、左侧伸展、仰卧、蜷缩仰卧、松散半仰卧、睡眠香箱。
- 枕头睡姿：头趴枕头、紧凑半仰卧、整身蜷睡。

飞流有 5 种无道具睡姿、4 种猫窝睡姿和两个场景坐姿。五百与飞流使用各自独立的动作图，不共享随机计时，也不做碰撞或互动。App 名称、运行时和宠物身份已经分离，以后增加朋友委托的宠物时，App 仍然叫 `PetsGraph`。

## 双宠运行方式

同一个 PetsGraph App 进程内装载多个独立宠物包：

- 首次安装默认同时装载两只宠物，五百和飞流都从默认睡姿开始。
- 两只宠物默认位于屏幕左下角，五百在左、飞流在右，横排且不重叠。
- 五百和飞流各自拥有独立随机时钟、动作状态、拖动位置和中文睡姿菜单，不会同步翻身。
- 菜单可以分别装载或卸载每只宠物，也可以装载全部。重新装载后从该宠物默认睡姿开始。
- 全局大小可以选择 `0.5×`、`0.75×`、`1.0×`、`1.25×`、`1.5×`、`1.75×` 或 `2.0×`，同时作用于全部宠物并保持各自地面锚点。
- 飞流使用自己的无道具与猫窝动作图，视觉基准比五百大 5%。两只宠物不共享动作图，也不做碰撞和互动。

v0.5.10 通过 67 项 XCTest，并完成两个包共 84 个 clip、12,013 帧的结构、完整性和媒体校验。每条动作使用覆盖整段内容的固定正方形透明窗口，超宽制作画布不会直接变成桌面留白。双宠首次布局、菜单、拖动、倍率、独立随机时钟、猫窝场景位移和透明边缘已经完成真实桌面人工验收。

## 为什么是睡觉陪伴

PetsGraph 最初验证过走路、跑步和真实桌面位移。真正长时间使用后，我们发现最舒服的体验并不是让宠物完成任务，而是偶尔抬眼就能看见熟悉的宠物在桌面角落安心睡觉。

因此第一个版本只做安静陪伴。已完成的走跑素材与 root motion 工程能力继续保留，但不进入公开版的默认行为。

## 动作不是随机硬切

每个稳定姿态是节点，循环动作和有向过渡是边。运行时只在安全退出帧离开循环，提前加载下一条边，并逐帧播放完整过渡。

评审视频会把所有姿势串成固定闭环，方便检查每一处接缝；正式运行不是照这个顺序轮播，也不是从十个视频里随机抽一个硬切。宠物会在当前动作图上进行低频随机游走，避开最近出现的姿势，并降低跨场景和偶发活动的频率。例如：

```text
趴卧
  → 左侧蜷卧
  → 左侧伸展
  → 仰卧
  → 返回趴卧
```

带枕头的睡眠属于完整场景。枕头只通过已经验收的进出场动作出现或离开，并在场景内保持位置、尺度和接触关系连续。

## 每只宠物单独定制

PetsGraph 不再追求“上传任意宠物照片，就自动生成一套通用动作”的产品路线。五百、飞流和未来朋友委托制作的宠物，可以拥有不同的睡姿数量、道具、动作图、随机权重和小习惯。

项目仍然复用离线运行时、素材包、任务账本、抠图、完整性校验和低功耗渲染，但宠物身份、姿势、承重、动作连接与最终验收由人工逐只完成。飞流当前采用无道具和猫窝两个睡眠场景。通过人工验收的素材图包含 11 个节点、20 条有向边和 31 个唯一素材：

```text
正面坐姿 ↔ 平趴睡 ↔ 侧身伸展睡
                     ↔ 紧蜷睡
                     ↔ 半仰睡 ↔ 仰躺睡
                     ↔ 猫窝蜷睡 ↔ 猫窝正面坐姿
                                  ↔ 猫窝自然趴睡
                                  ↔ 猫窝侧伸睡
                                  ↔ 猫窝舒展露腹睡
```

平趴睡和猫窝蜷睡分别是两个睡眠子图的枢纽。正式运行会在这张图上低频随机游走，不按上面的排版顺序固定轮播。飞流精抠整链、运行时包和真实桌面随机行为均已通过。此前制作的毛毯素材和生成记录继续保留，但不会进入飞流首版宠物包。

## 为什么安装包比较大

v0.5.10 内置两个宠物包，共 84 个逐帧动作片段和 12,013 个运行时帧。获批透明素材继续作为制作事实源保留，不会被修改或删除；公开 App 使用由它们确定性编译的固定裁剪预乘 RGBA 副本。

解压后的 App 约 2.4 GiB，用存储空间换取更低的长期运行开销。v0.6.0 macOS DMG 为 `857640594` 字节，约 818 MiB。Release 不上传 App ZIP，也不重复上传独立 `.petsgraph-pet`。

Windows v0.6.0 ZIP 为 `913953281` 字节，约 872 MiB。它除了相同的双宠运行时媒体，还包含自包含 .NET 10 运行文件，因此用户不需要另行安装 .NET。

本机真实桌面测量中，普通睡眠约占 1.3% 到 1.6% CPU，物理内存占用约 53 MiB；连续换姿约占 2.1% 到 2.7% CPU，物理内存占用约 19 到 46 MiB。由于运行时使用只读内存映射，部分工具显示的 RSS 可能约为 110 到 117 MiB，这不等于同等规模的实际内存压力。不同 Mac 和系统版本的数值会有差异。

## 验证状态

- 两个宠物包共 84 个逐帧动作片段和 12,013 帧。
- 五百包含 14 个姿态节点和 39 条有向边；飞流包含 11 个姿态节点和 20 条有向边。
- v0.6.0 macOS App 通过 67 项 XCTest，DMG 通过只读挂载、arm64、Bundle 版本、Logo 哈希、ad-hoc 签名、双宠包和运行时完整性校验。
- 两个包均为 schema `0.4.0`、`cropped-rgba-clips`、`runtime-chain-approved` 和 `installable=true`。
- 五百与飞流的获批源素材继续作为制作事实源保留，公开 App 只内嵌确定性编译的低功耗副本。
- Windows v0.6.0 通过 7 项 MSTest、WPF 编译、AMD64 PE、ZIP、双宠完整性和 GitHub Windows Runner 校验，真实 Windows 11 x64 使用验收反馈为没有问题。

正式 App 和大型运行时素材随 [GitHub Release](https://github.com/iyuenan3/petsgraph/releases) 分发，不把数百 MB 的资源写入 Git 历史。原始宠物照片、Seedance 任务记录、被拒绝的候选和私有生产上下文不会公开。

## Codex 宠物导出

仓库同时维护五百和飞流的 Codex v2 自定义宠物图集，位于 [`codex-pets/`](codex-pets/)。它们是可以直接安装到 Codex 的小型独立导出，不是 PetsGraph App 的连续视频动作包，也不替代上面的正式运行时验收结论。

```bash
python3 tools/manage-codex-pets.py validate
python3 tools/manage-codex-pets.py install
```

安装器默认同时安装两只宠物，并在覆盖不同内容前停止。完整清单、哈希、单只安装与可恢复替换方式见 [`codex-pets/README.md`](codex-pets/README.md)。

## 仓库结构

- `Sources/PetsGraphCore/`：宠物包校验、动作图、时间轴与 root motion。
- `Sources/PetsGraphApp/`：AppKit 透明窗口、逐帧渲染、菜单和桌面交互。
- `windows/src/PetsGraph.Core/`：跨平台 C# 包校验、行为图、时间轴和 RGBA 转换。
- `windows/src/PetsGraph.App/`：Win11 x64 WPF 透明窗口、托盘菜单和桌面交互。
- `windows/scripts/`：Windows 自包含运行时和便携 ZIP 打包脚本。
- `codex-pets/`：五百与飞流的 Codex v2 宠物导出、完整性清单和安装说明。
- `tools/manage-codex-pets.py`：校验 Codex 图集契约并安全安装到本机 Codex 数据目录。
- `tools/build-prototype-package.py`：把固定 PNG 事实源编译为版本化宠物包。
- `tools/build-cropped-rgba-package.py`：从获批 PNG 包生成固定 clip 裁剪的低功耗运行时副本。
- `tools/build-macos-app.py`：把已校验宠物包嵌入通用 PetsGraph App。
- `tools/build-release-artifacts.py`：原子生成并校验 macOS 安装 DMG，App 版本和已批准宠物包版本分别记录。
- `.github/workflows/release.yml`：使用只读权限复验公开 Release 的不可移动标签、双平台精确附件集合、哈希、Bundle 身份、Logo 和 arm64 架构。
- `.github/workflows/windows-release-verify.yml`：在 Windows Runner 上按双平台清单校验草稿 Release 的 Windows ZIP、字节数、SHA-256、版本、AMD64 PE 和双宠完整性。
- [`AIREADME/CORE.md`](AIREADME/CORE.md)：产品身份、范围和红线。
- [`AIREADME/SPEC.md`](AIREADME/SPEC.md)：宠物包、动作图、场景和交互契约。
- [`AIREADME/DEPLOYMENT.md`](AIREADME/DEPLOYMENT.md)：构建、安装、发布和回滚方式。

## 本地开发

运行 Swift 测试：

```bash
bash tools/test-swift.sh
```

运行 .NET 测试和 Windows 交叉编译：

```bash
DOTNET_CLI_HOME=/tmp/petsgraph-dotnet-home ~/.dotnet/dotnet test windows/tests/PetsGraph.Core.Tests/PetsGraph.Core.Tests.csproj -c Release
DOTNET_CLI_HOME=/tmp/petsgraph-dotnet-home ~/.dotnet/dotnet build windows/PetsGraph.slnx -c Release
```

生成完整 Windows 便携包时，通过 `PETSGRAPH_PETS_DIR` 指向已批准的双宠包目录：

```bash
PETSGRAPH_PETS_DIR=/path/to/Pets bash windows/scripts/build-portable.sh
```

本地生产构建、校验和发布流程见 [`AIREADME/DEPLOYMENT.md`](AIREADME/DEPLOYMENT.md)。私有制作侧可以使用 Seedance 生成连续动作视频，并使用 Seedream 或 `gpt-image-2` 制作静态身份和姿态参考。所有凭据只保存在被 Git 忽略的本机配置中，不会进入桌面运行时、宠物包或 Release。

## 致谢

感谢朋友制作的 [麻薯 Mochi](https://mochi.xin/)。PetsGraph 立项时参考了它在透明桌面窗口、宠物素材生成和桌面陪伴体验上的探索，并在此基础上选择了安静睡眠陪伴、完整动作图与开源素材包这条更聚焦的方向。

## License

运行时代码和维护工具使用 [MIT License](LICENSE)。五百和飞流的 PetsGraph 动画素材与 Codex 宠物图集可以用于个人桌面陪伴，其他使用边界见 [ASSETS.md](ASSETS.md)。
