# DEPLOYMENT：petsgraph

## 状态与下一代分发目标

当前可下载的 `v0.6.0` 仍是内嵌五百与飞流的历史正式版，下面的安装、摘要和双平台发布流程继续作为该版本的事实与回滚依据。Apple Silicon macOS 与 Windows x64 `0.7.0-dev` 均已实现零素材 Player、外部 `.petpack` 装载和内部宠物库，但尚未完成真实桌面人工验收或正式发布。不能用开发实现替换当前公开安装说明。

下一代发布边界：

- Apple Silicon macOS 与 Windows x64 Player 分别发布，但两个安装包都不包含真实宠物素材。
- Player 源码、PetPack 规范、验证器、合成测试资产和发布流程公开。
- Seedance 等制作工具、客户目录、未公开母片和未来正式 PetPack 保持私有，不进入公开 Player 发布物。五百与飞流已经公开的历史素材继续按 `ASSETS.md` 保留，不再内嵌到下一代 Player。
- 用户从 Maxwell 获得 `.petpack` 后自行长期保存，通过 Player 的“装载宠物包…”导入内部 canonical 库。
- Player 二进制、canonical 宠物库与可重建 cache 分目录保存。升级只能替换应用和可重建 cache，不能修改或删除已装载宠物。
- 普通卸载 Player 默认保留内部宠物库；彻底删除用户数据必须单独确认。卸载某只宠物则删除内部包及其本地状态，之后需要原始 `.petpack` 才能恢复。
- 当前不构建 iPadOS、电视端、Intel Mac、Windows on Arm 或 32 位 Windows，但 PetPack 1.0 不能包含桌面窗口、平台路径或特定 OS 行为。

下一代应用继续使用名称 `PetsGraph`，macOS 保留 Bundle ID `com.maxwell.petsgraph`，Windows 保留 `PetsGraph` 应用身份。macOS 数据根为 `~/Library/Application Support/PetsGraph/`，Windows 数据根为 `%LOCALAPPDATA%\PetsGraph\`；两个平台都分离 canonical PetPack、可重建 cache、`registry.json` 和 `settings.json`。开发阶段版本使用 `0.7.0-dev`，五百、飞流和双平台 Player 通过后发布 `1.0.0`。

PetPack 1.0 使用普通 ZIP 容器和必需的 `cropped-rgba-clips` 基础表示。五百与飞流首批包只有完整性哈希，不带官方签名；签名、公证、Windows 代码签名和可选紧凑媒体均属于后续增强。历史 `v0.6.0` 路径和摘要不因新方向而改写。

### PetPack 1.0 公开契约验证

公开契约已经实现，当前不依赖私有 Studio、真实宠物包或第三方 Python 包：

```bash
python3 -m unittest discover -s petpack/tests -v
python3 -m petpack.validator petpack/fixtures/synthetic-cat-v1.petpack
python3 -m petpack.validator petpack/fixtures/synthetic-cat-forward-v1.petpack
python3 -m petpack.tools.build_fixture /tmp/petsgraph-synthetic-cat-v1.petpack
cmp petpack/fixtures/synthetic-cat-v1.petpack /tmp/petsgraph-synthetic-cat-v1.petpack
python3 -m petpack.tools.build_fixture \
  --forward-compatible /tmp/petsgraph-synthetic-cat-forward-v1.petpack
cmp petpack/fixtures/synthetic-cat-forward-v1.petpack \
  /tmp/petsgraph-synthetic-cat-forward-v1.petpack
```

当前回归为 33 项。基线合成包共 12 个文件、11,806 bytes，SHA-256 为 `812f0459fe444ff4cf657908d3c9b235be21f591d796ac7d0f02e50f564ac2c1`；前向兼容合成包共 12 个文件、11,774 bytes，SHA-256 为 `d0f5273cbf930e2ddd12865a62311d0d2058c4a1749b07b33448d84411ca08dc`。两包只包含程序生成的 2×2 RGBA 像素，后者声明未知可选能力 `future-audio` 并省略节点与场景权重覆盖。通过这些检查只证明公开容器与语义契约，不证明五百、飞流转换、Player 导入、平台解码或真实桌面表现。

### 五百与飞流 PetPack 1.0 私有候选

私有 Studio 已从两个 `0.5.10` 旧批准包生成 `contentVersion=1.0.0` 候选：

| 宠物 | 私有候选 | clip | 节点 | 边 | bytes | SHA-256 |
|---|---|---:|---:|---:|---:|---|
| 五百 | `petpacks/personal/wubai/candidates/wubai-quiet-companion-1.0.0.petpack` | 36 | 12 | 26 | 1,068,381,496 | `14f719b67da95a4cf089500aedc7c67fb6c74c3a63a273052190856f99b3e0ef` |
| 飞流 | `petpacks/personal/feiliu/candidates/feiliu-quiet-companion-1.0.0.petpack` | 25 | 9 | 16 | 596,024,359 | `f0308cd322fbbd1ef1259e64ca3f93a8f7da58b202aa441baef5a26fe61aef25` |

转换前完整回读旧 integrity，转换后公开验证器通过，旧媒体到新媒体的字节数与 SHA-256 不匹配数均为 0。两个候选分别重复构建一次，前后包级 SHA-256 不变。五百排除 2 个 interaction 节点、2 个网关停留循环及 15 个其他交互 clip，保留两条场景过渡的像素，但不携带其旧窗口 root motion；飞流排除 2 个 interaction 节点及 6 个交互 clip。候选状态均为 `mechanically-validated-awaiting-player-runtime-review`，尚未进入 `approved/` 或 `delivery/`，不能作为 Player 或真实桌面验收通过。

## macOS v0.6.0 发布基线

PetsGraph `0.6.0` 是 Apple 芯片专用双宠正式版，最低支持 macOS 14。App 名称为 `PetsGraph`，Bundle ID 为 `com.maxwell.petsgraph`，使用 ad-hoc 签名，尚未使用 Developer ID 或 Apple 公证。App 使用新的双猫相伴 Logo，继续内嵌已经验收的两个 `0.5.10` 宠物包。

| 宠物 | 内嵌包 | clip | 帧 | `baseHeightPt` | 状态 |
|---|---|---:|---:|---:|---|
| 五百 | `wubai-quiet-companion-0.5.10` | 53 | 6,866 | 172.5 | `runtime-chain-approved`、`installable=true` |
| 飞流 | `feiliu-quiet-companion-0.5.10` | 31 | 5,147 | 181.125 | `runtime-chain-approved`、`installable=true` |

两包均使用 schema `0.4.0` 与 `cropped-rgba-clips`。飞流在 1.0× 下比五百大 5%。v0.6.0 正式 DMG 的本地可下载副本现归档在 `.local/dist/published/v0.6.0/`，GitHub Release、标签与 `release/manifests/v0.6.0.json` 才是发布事实源。App 版本与宠物内容版本分别记录，不为 Logo 更新重新编译或改写 12,013 帧已批准媒体。

DMG 固定属性：

- 字节数：`857640594`
- SHA-256：`04c6f30e35d7dd8b5b096d0051aad628987d59b8245d84060cf704f02709b159`
- 主可执行架构：严格为 `arm64`
- 内嵌 ICNS SHA-256：`8b976a2ebe6badbcd6709201a03dc5900ed45c7bad01d4a210fde8cdbf38c24d`

v0.6.0 Release 共有两个附件，一个 macOS DMG 和一个 Windows ZIP。它不提供 App ZIP、预览图、校验和附件或独立 `.petsgraph-pet`。两个附件哈希记录在 `release/manifests/v0.6.0.json`。

## Windows v0.6.0 发布基线

Windows `0.6.0` 只面向 Windows 11 x64 与知情的内部朋友。它使用 .NET 10 WPF，以 self-contained 多文件便携 ZIP 交付，不需要用户预装 .NET。当前不构建 MSIX、安装器或代码签名。

冻结发布产物：

- 本地副本路径：`.local/dist/published/v0.6.0/PetsGraph-v0.6.0-Windows-x64.zip`
- 字节数：`913953281`
- SHA-256：`90578d6620ef9c221c173b173c24631d6e756b372b532030f8669994d22b0015`
- ZIP 条目：`488`
- 内嵌宠物包：`2`，五百与飞流
- 主程序：PE32+ GUI，x86-64

该 ZIP 已在 macOS arm64 本机使用 .NET SDK `10.0.400` 交叉发布，并通过压缩数据、无 `__MACOSX`/`.DS_Store`、双包数量和真实包完整性校验。7 项 MSTest、WPF 编译、GitHub Windows Runner 与朋友真实 Windows 11 x64 使用验收均已通过，朋友反馈没有问题，发布所有者明确授权发布 v0.6.0。真机反馈没有附带分项时长或 DPI 日志，因此只记录最终结论。历史根 `dist/` 已退出，冻结 ZIP 的本地副本与 DMG 一起位于 `.local/dist/published/v0.6.0/`。

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

## macOS `0.7.0-dev` 本机构建与验证

测试必须使用完整 Xcode 基线：

```bash
bash player/macos/scripts/test.sh
```

构建零宠物素材开发 App：

```bash
python3 player/macos/scripts/build-app.py \
  --output /private/tmp/PetsGraph-0.7.0-dev.app \
  --version 0.7.0-dev
```

当前 main 的构建器只产生 Apple Silicon、ad-hoc 签名、零宠物素材 App。输出只能位于仓库或系统临时目录，人工安装候选优先放在 `/private/tmp`。Desktop 的 File Provider 可能在签名后异步重新加入 `com.apple.FinderInfo`，导致严格签名复验失败，所以不要把 Desktop 同步目录当作安装候选事实源。构建器在打包前调用原生 `--validate-only` 读取公开合成 PetPack，并在打包后复验架构、签名、包身份和零素材边界。GitHub 的 `.github/workflows/macos.yml` 运行 33 项公开 PetPack 回归、27 项 Swift 测试并上传保留 7 天的代码开发 App。

本地已验证：

- Swift 严格警告编译与 26 项测试通过，新增回归使用飞流、五百两种舞台比例和带负坐标屏幕直接证明可见裁剪框能贴到上下左右四条边；其余回归继续覆盖双宠状态往返、卸载事务恢复、独立随机时钟、旧运行时只迁移位置和全局大小、首装、更新与进程中断回滚、损坏设置和行为预加载失败。
- 公开 store 基线包、前向兼容包、临时 deflate 合成包、五百和飞流真实候选均由 Swift 原生加载器验证通过。
- App 主可执行文件为 `arm64`，`codesign --verify --deep --strict` 通过。
- App 不包含 `Resources/Pets`、`.petpack` 或真实宠物媒体。
- 当前已安装 App 来自 `/private/tmp/PetsGraph-0.7.0-review13.app`，版本 `0.7.0-review`、构建号 13，主程序为 1,216,288 bytes，SHA-256 为 `65fb9b16f90f90ea85e5efac83de00556a27a09b97fccb843e8787f64aabd479`。构建后与安装后的严格签名通过，主程序为 `arm64`，App 资源只有 `PetsGraph.icns`，没有 `.petpack`、`Resources/Pets` 或真实宠物素材。Info.plist 导出 `com.maxwell.petsgraph.petpack` 并把 `.petpack` 注册为可打开文档类型。
- build 6 完成构建但从未安装。build 7 完成安装和双宠稳定态 A/B 后由 build 8 取代，build 8 完成首次低 CPU 动作链后由增加四边公式回归的 build 9 取代，build 9 又由改善装载导航的 build 10 取代，build 10 再由增加系统文件关联的 build 11 取代，build 11 由修正菜单灰显的 build 12 取代，build 12 最后由修正 Dock 遮挡的 build 13 取代。build 5、build 7、build 8、build 9、build 10、build 11 与 build 12 均以带构建号和时间的名称可恢复保存在系统回收站。
- build 4 已在真实 macOS 桌面启动五百与飞流。对两只默认睡眠循环分别取得 4 个正常速度画面摘要，画面持续缓慢变化且锚点不动；通过设置状态重启验证了单只隐藏、双宠显示、1.0 与 2.0 全局倍率恢复。自动化测试留下的 `Synthetic Cat` 彩色夹具资料库已完整移入系统回收站，真正空库启动没有宠物窗口。
- 同一五百候选的原生 `--validate-only` A/B 中，build 3 最大常驻内存为 2,162,049,024 bytes，build 4 为 19,333,120 bytes。双宠 GUI 的 `vmmap` 物理占用由修前 1.6 GB 降至 55.8 MB，稳定取样约 3.3% CPU，唯一当前进程没有崩溃报告。该结果只覆盖默认睡眠循环，不替代长时间过渡、菜单、透明命中、拖动、卸载和用户视觉批准。
- build 4 双宠持续运行 17 分钟后的补充回读仍只有一个进程，当前物理占用 53.7 MB、峰值 55.9 MB、CPU 约 3.4%，没有新增崩溃报告。媒体映射显示两只仍在各自默认睡眠循环，因此只能证明稳定态资源没有持续增长，不能证明完整动作切换。
- build 4 在飞流与五百分别进入首轮动作链后，旧 RGBA 映射和逐帧图像没有释放，物理占用达到 287.6 MB。`8749ea6` 将缓存边界收敛为当前片段及尚未执行的完整预载链。
- build 5 中飞流与五百分别在 21 分 12 秒与 28 分 42 秒进入真实多段动作链。预载映射随路径执行逐段减少，进入两个新稳定循环后只保留 `cat-bed-prone-loop-v1` 与 `semi-supine-left-loop-v1`；物理峰值为 126.1 MB，稳定回读为 46.7 MB。60 Hz 版本十次稳定态 CPU 取样平均为 2.98%。
- build 7 安装后默认双宠稳定态约为 3.0% CPU，证明只改原生帧率与删除每帧 Swift `Task` 没有形成可声明的 CPU 下降。5 秒进程采样把主要重复成本定位到每帧立即提交 Core Animation 事务、重复写入相同窗口事件掩码和相同图层几何。
- build 8 的相同默认双宠稳定态十次 `top` 取样为 `0.9, 0.9, 0.9, 1.0, 0.9, 0.9, 1.0, 1.0, 1.1, 1.1`，平均 0.97%。`vmmap` 初次稳定回读的物理占用为 55.4 MB、峰值 55.5 MB，运行 7 分 32 秒后为 54.3 MB、约 0.9% CPU，并且没有新增崩溃报告；进程只映射飞流 `no-prop-prone-loop-v1` 与五百 `prone-left-long-loop-v1`。2.5 秒间隔窗口图像摘要不同，排除停帧或隐藏宠物造成的低 CPU 假象。进一步降低这组内存需要改变 PetPack 原始 RGBA 表示或增加反复缺页，必须先通过流畅度与透明边缘对照，不能作为无风险微优化。
- build 8 运行 17 分 5 秒后，五百从趴卧经侧蜷过渡进入侧伸展循环。过渡时只保留两条待执行边、目标循环和飞流当前循环，物理占用为 26.8 MB；21 秒后只剩两只当前循环，物理占用为 29.6 MB、CPU 约 0.9%，进程峰值仍为 55.5 MB。该证据证明低 CPU 提交路径没有破坏自主切换或有界缓存。
- build 9 安装后的默认双宠稳定态十次 `top` 取样为 `0.9, 0.9, 1.0, 1.0, 1.1, 1.0, 1.0, 0.9, 1.0, 1.0`，平均 0.98%；物理占用为 55.7 MB、峰值 55.8 MB，2.5 秒间隔窗口图像摘要不同。提交 `ded3df1` 的 macOS 运行 `32631375700` 成功。
- build 10 在系统装载窗口显示文件夹双击和 `⌘⇧G` 提示，首次使用从下载目录开始，成功选择后记忆上次目录。用户确认卸载成功后，`registry.json` 为 0 个宠物，`Library`、`Cache` 与 `Staging` 均为空；代码提交 `76856e0` 的 macOS 运行 `32632413985` 通过。
- build 11 注册 `.petpack` 系统文件类型，并通过系统直接打开入口依次装载五百和飞流。内部注册表正好包含 2 个包，两个 canonical copy 的 SHA-256 与用户保存的原始候选一致，最近装载目录已记忆；用户在真实桌面明确确认已经装载。十次即时 CPU 取样为 `0.0, 0.7, 1.1, 1.2, 1.2, 1.1, 1.1, 1.2, 1.1, 1.1`，平均 0.98%；物理占用为 65.9 MB、峰值 66.2 MB。该取样紧随两次装载结果窗口，不作为无弹窗稳定态内存对比结论。`feaf6cd` 的 macOS 运行 `32632984632` 成功。
- 用户在 build 11 上确认显示和隐藏通过。`5e7f516` 与 build 12 关闭菜单自动启用，确保手工计算的当前状态不会被 AppKit 覆盖；升级后回读内部资料库仍为五百和飞流两个包，当前两只均显示。用户随后确认目标状态灰显通过。`5e7f516` 的 macOS 运行 `32633124523` 成功。
- build 12 双宠无装载弹窗稳定运行后，`top` 首个初始化样本为 0.0%，后 9 次 CPU 平均为 0.99%；`vmmap` 物理占用为 53.6 MB、峰值 54.0 MB。进程只映射飞流 `no-prop-prone-loop-v1` 与五百 `prone-left-long-loop-v1`，启动后没有新的崩溃报告。该状态是当前日常双宠资源基线，但仍不能替代正常速度视觉批准。
- `c9e9790` 与 build 13 将宠物面板从普通浮动层级 3 改为 Dock 层级加 1。安装态两个宠物窗口的实际层级均为 21，高于 Dock 的 20，低于系统主菜单的 24；内部资料库升级后仍为五百与飞流两个包。当前屏幕为 2056×1329，Dock 占用底部 89 点；五百窗口底部换算为 -26，飞流为 -32，均已进入 Dock 占用区，窗口服务器仍把两者排在 Dock 前方。26 项 Swift 测试、严格格式、构建后与安装后签名、零素材检查均通过，远端 macOS 运行 `32634129068` 成功。Computer Use 拖动继续返回 `AXError.notImplemented`，但用户已经用真实鼠标确认可以从 Dock 区域拖出。
- build 13 运行约 14 分钟后的十次 `top` 取样首个样本为 0.0%，后 9 次 CPU 平均为 0.70%，内存列稳定为 54 MB；`vmmap` 物理占用为 54.3 MB、峰值 55.1 MB。进程仍只映射飞流 `no-prop-prone-loop-v1` 与五百 `prone-left-long-loop-v1`，Dock 层级修复没有造成可见资源回退。
- `901b364` 与 build 14 修正 macOS 位置持久化。保存设置前会从全部实际窗口回收经过缩放或屏幕限位后的锚点和可见状态，避免旧锚点在重启或下一次缩放时重新生效。新增回归后 27 项 Swift 测试、严格格式、Release 构建、arm64、零素材和严格签名均通过；主程序为 1,216,928 bytes，SHA-256 为 `05ca70761304f65874cc5de5988b557f10e58ff56a4395c725ad91c145f2e342`。安装后首次启动恢复五百和飞流两个窗口，实际层级仍为 21。远端 macOS Apple Silicon 运行 `32636187517` 成功。build 13 保存在 `~/.Trash/PetsGraph-build13-20260823-191918.app`，可以恢复。
- build 14 双宠稳定态十次 `top` 取样为 `0.0, 0.5, 0.9, 0.8, 0.8, 0.8, 0.8, 0.7, 0.7, 0.7`，排除首个样本后平均为 0.74%；`vmmap` 物理占用为 53.3 MB、峰值 56.0 MB。进程只映射飞流 `no-prop-prone-loop-v1` 与五百 `prone-left-long-loop-v1`，没有显示相对 build 13 的资源回退。

上述结果不替代真实 macOS 桌面上的菜单、拖动、透明命中、多宠并发、隐藏恢复、应用升级保留和正常速度视觉验收。

## macOS `v0.6.0` 历史构建基线

`v0.6.0` 的内嵌双宠构建器已经从 main 删除。若需要重现旧 App，必须在独立工作区检出不可移动的 `v0.6.0` 标签，并使用标签内的旧 `build-legacy-app.py`、旧源码路径和冻结宠物包。不要在当前 main 伪造兼容入口。

历史版本构建唯一发布附件的命令为：

```bash
.local/environments/core/bin/python studio/packaging/build-release-artifacts.py \
  --app .local/dist/builds/PetsGraph-0.6.0.app \
  --output .local/dist/builds/v0.6.0 \
  --version 0.6.0
```

历史正式构建必须通过：

- 67 项 XCTest。
- 两个包的 schema、独立包版本、批准状态、图、完整性和全部 12,013 帧媒体校验。
- App 主可执行文件 `arm64` 架构检查。
- `codesign --verify --deep --strict`。
- `hdiutil verify`，只读挂载后再次检查 App、签名、版本、ICNS 哈希和两个内嵌包。
- 发布目录精确只有一个 DMG，本地字节数和 SHA-256 与双平台仓库清单中的 macOS 条目一致。

DMG 使用本机 `/usr/bin/hdiutil create` 从冻结 App 构建。GitHub Actions 不重新编译媒体或 App。公开后的 macOS 工作流只使用 `contents: read` 下载、校验和挂载已发布附件，不具备发布权限。本机受限沙箱可能让 `hdiutil` 报“设备未配置”，此时必须确认没有残留半成品，再以明确的磁盘映像权限重跑同一确定性命令。

## Windows `0.7.0-dev` 构建与验证

仓库用 `player/windows/global.json` 锁定 .NET SDK `10.0.400`。macOS arm64 本机 SDK 安装在 `~/.dotnet`，未修改用户全局 PATH。依赖先按锁文件还原，核心命令：

```bash
DOTNET_CLI_HOME=/private/tmp/petsgraph-dotnet-home \
  ~/.dotnet/dotnet test player/windows/tests/PetsGraph.Core.Tests/PetsGraph.Core.Tests.csproj \
  --configuration Release --no-restore --disable-build-servers -m:1 \
  -p:UseSharedCompilation=false -p:NuGetAudit=false

DOTNET_CLI_HOME=/private/tmp/petsgraph-dotnet-home \
  ~/.dotnet/dotnet build player/windows/PetsGraph.slnx \
  --configuration Release --no-restore --disable-build-servers -m:1 \
  -p:UseSharedCompilation=false -p:NuGetAudit=false

DOTNET_BIN=~/.dotnet/dotnet \
DOTNET_CLI_HOME=/private/tmp/petsgraph-dotnet-home \
  bash player/windows/scripts/build-portable.sh
```

`build-portable.sh` 拒绝覆盖同名 ZIP，先用 C# 原生验证器检查公开合成 PetPack，再交叉发布 `win-x64` self-contained 应用，强制产物不含 `Pets/` 或 `.petpack`，最后执行 ZIP 解压测试与 SHA-256。当前本地机械证据：

- 43 项 MSTest 通过，覆盖 store、deflate、未知可选能力与默认权重、严格 ZIP、重复 JSON key、路径越界、大小写冲突、符号链接、摘要不符、canonical copy、cache 重建、首装与更新回滚、进程中断恢复、事务卸载及其注册表提交前后恢复、双宠状态与统一倍率往返、不安全安装索引、损坏设置、独立行为与独立随机时钟、隐藏过渡、RGBA 到 PBGRA、长时间帧索引、全局大小、旧状态迁移、缓存淘汰和语义版本。
- WPF 与全解决方案 Release 构建为 0 警告、0 错误；`dotnet format` 空白校验通过。
- C# 原生验证器通过公开 store 基线包、前向兼容包、临时 deflate 合成包、五百和飞流真实候选，五个包的 SHA-256 分别与参考验证器和私有转换记录一致。
- 当前本地零素材 ZIP 为 75,267,412 bytes，SHA-256 为 `6d90aa7cada380a30d8a348cac1a5e3c6806ca67ca08be7a135b31da036abac8`。该 ZIP 可完整解压，主程序由 `file` 识别为 `PE32+ executable (GUI) x86-64`，内部没有 `Pets/` 或 `.petpack`。它只是当前机械证明，不是冻结交付物或 Release 附件。
- `.github/workflows/windows.yml` 已在 `97485a0` 的 `windows-2025` Runner 上通过锁定还原、20 项测试、WPF 构建、零素材 self-contained ZIP、AMD64 PE、内容检查和代码开发产物上传。
- 真实 Windows 11 x64 上的透明命中、DPI、拖动、托盘、多显示器、隐藏恢复、应用升级保留和长时间正常速度观看仍是人工闸门。

当前开发 ZIP 没有代码签名，可能触发 SmartScreen。正式 `1.0.0` 之前还必须在真实 Windows x64 机器运行 PowerShell 打包入口和 GUI 验收，冻结人类看过的候选，再决定是否增加代码签名或安装器。

本轮 12 项重构要求、清理恢复点、双平台产物摘要和逐项人工门禁统一记录在 `docs/audits/refactor-2026-08-23.md`。该记录明确保持 Goal 未完成，不得用自动化测试替代真实桌面批准。

首次把重构提交推送到远端后，macOS Apple Silicon 工作流在 `a7c2cb5` 通过。PetPack contract 的 Windows job 暴露 Python `ZipInfo.filename` 会把原始反斜线规范化，Windows x64 job 另暴露 .NET `ZipArchive` 在 Windows 上不会自动把 Unix 权限位标记为 Unix 创建主机。`1937a03` 改为验证 `orig_filename` 并让测试写入真实原始路径，`f6b855f` 让 C# 恶意 symlink 测试包在所有平台固定中央目录创建主机。修复后远端 `main` 回读为 `97485a0c5ccc557748773738dac5e009cf221753`，PetPack contract 运行 `32596460282`、macOS 运行 `32596460260`、Windows 运行 `32596460309` 均通过。远端上传的 macOS 与 Windows 代码开发产物分别为 1,806,750 和 77,508,772 bytes，保留 7 天。完整步骤回读见 `docs/audits/refactor-2026-08-23.md`。

最终审查代码推送后，PetPack contract 运行 `32600312955` 在 `8b8f902` 通过，macOS 与 Windows 运行 `32600330583`、`32600330777` 在 `b417a6b` 通过。历史公开 Release 的新只读流程也已真实触发：macOS 运行 `32600568305` 从 `v0.6.0` 标签执行历史 Swift 基线、双附件摘要和 DMG 挂载复验，Windows 运行 `32600570363` 使用 `contents: read` 完成 ZIP 摘要、AMD64 PE、双包和运行时完整性复验。五个运行均成功。

状态恢复与卸载事务加固继续以两个独立切片推送。最终代码提交 `c48cf52` 的 macOS 运行 `32626778829` 通过 25 项 Swift 测试、零素材 arm64 App 构建和上传，Windows 运行 `32626778828` 通过 42 项 MSTest、WPF、self-contained x64 ZIP、零素材检查和上传。

### Windows `v0.6.0` 历史 Release 复验

`.github/workflows/windows-release-verify.yml` 当前只复验已经公开的 `v0.6.0` Windows ZIP，不创建标签、不上传附件、不修改 Release，并且只授予 `contents: read`。流程从不可移动的 `v0.6.0` 标签检出历史源码与清单，要求公开附件集合与清单严格一致，再核对字节数、SHA-256、版本、AMD64 PE、双包数量和运行时完整性。它不再把当前 main 的重构路径与历史标签比较，也不能读取草稿 Release。

两个 v0.6.0 Release 复验工作流都从不可移动标签读取历史实现，并只读校验已经公开的冻结附件。提交 `84bbc5e` 之后的 `main` 不再把这两个历史工作流当作新 Player 的 CI；PetPack 1.0 与零素材 Player 必须建立独立的 1.0.0 构建和发布门禁。

## v0.6.0 GitHub 双平台发布流程

1. 冻结真实 Windows 11 x64 验收过的 ZIP 和本机只读挂载验证过的 macOS DMG，记录精确名称、字节数和 SHA-256。
2. 提交 README、`docs/releases/v0.6.0.md`、双平台 `release/manifests/v0.6.0.json`、打包器和两个验证工作流，再以该内容提交为锚点更新 AIREADME。
3. 保持带注释标签 `v0.6.0` 不移动。该标签固定指向 `ce4570cef6f47fe75b32df40c1476b0657a1d999`，其中已经包含两个平台宿主与双猫 Logo。默认分支上的发布补充必须验证平台源码相对标签无变化。
4. 使用 `docs/releases/v0.6.0.md` 维护草稿 Release，精确上传清单指定的 Windows ZIP 与 macOS DMG。上传过程长时间无输出时继续轮询原进程或回读远端状态，不重复上传，不使用 `--clobber` 覆盖未知状态附件。
5. 发布当时从默认分支触发 Windows 草稿复验，并经发布所有者明确授权只读使用具有草稿可见性的 token。当前工作流已经收紧为 `contents: read`，只能在发布后从 `v0.6.0` 标签复验公开双附件集合及 Windows ZIP 内容。
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
- 当前两个 Player 的 As-built 都由每个宠物窗口持有 60 Hz UI Timer，只在 clip 或帧实际变化时提交画面；每只宠物拥有独立行为会话和随机时钟。共享低开销 scheduler 仍是后续多宠优化目标，不能把历史 24 Hz 实现描述为当前事实。
- 双宠长期 CPU 与内存继续收集真实数据。性能结论必须注明唯一 PID、测量工具、稳定睡眠或过渡场景，不能把旧 AppTranslocation 进程计入当前版本。
- 下一版如改变素材、位置、体型、窗口命中、动作图或发布附件，必须重跑相应自动检查和真实桌面人工闸门。
- Windows 历史候选 ZIP 已清理，不用旧哈希冒充最新产物。后续重建写入 `.local/dist/builds/`，必须使用新版本名并重新记录字节数和 SHA-256，已上传的正式附件不原位覆盖。
- v0.6.0 的 DMG 与 Windows ZIP 本地副本位于 `.local/dist/published/v0.6.0/`，已于 2026-08-23 回读 GitHub Release 并核对文件名、字节数和 SHA-256。GitHub Release、标签、双平台清单和已批准宠物包共同构成回滚事实。
- Codex 导出使用稳定 ID 和 Git 历史回滚。更新现有视觉内容时新建版本化 ID；强制本地替换留下 `pets-backups`，不物理删除旧目录。
