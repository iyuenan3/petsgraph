# CHANGELOG：petsgraph

> Append-only。记录版本与里程碑，决策理由见 `DECISIONS.md`。

## Unreleased verification hardening · 2026-08-23

- Added: macOS 与 Windows 各新增双宠状态保存加载回归，覆盖单只隐藏、两组独立锚点、统一 `1.75` 倍恢复，以及已卸载宠物的陈旧状态不会重新进入运行态。
- Added: 两个平台各新增注册表提交前与提交后两个卸载中断恢复场景。提交前中断必须恢复原宠物和 canonical 数据，提交后中断必须完成清理且不能复活已卸载宠物。
- Review: Swift 25 项、MSTest 42 项、`swift-format lint --strict` 与 `dotnet format --verify-no-changes` 本地通过。代码切片 `0481211` 与 `c48cf52` 已分别推送并完成远端 `main` 回读，macOS 运行 `32626778829` 与 Windows 运行 `32626778828` 在最终代码提交上成功。
- Review: macOS build 4 双宠连续运行 17 分钟后仍为单进程，当前物理占用 53.7 MB、峰值 55.9 MB、CPU 约 3.4%，没有新增崩溃报告。两个媒体映射仍是各自默认睡眠循环，所以该证据只证明稳定态资源没有持续增长。
- Fixed: build 4 首轮真实动作链暴露出访问过的 RGBA 映射和逐帧图像永久保留。`8749ea6` 让 macOS 与 Windows 只保留当前片段及已计划的完整预载链，Windows 新增缓存淘汰回归，MSTest 增至 43 项。
- Review: build 5 中飞流和五百分别在 21 分 12 秒与 28 分 42 秒进入真实多段动作链。双宠切换物理峰值为 126.1 MB，进入两个新稳定循环后仅保留各自当前媒体并降至 46.7 MB；build 4 在旧缓存策略下首次双宠切换后已达到 287.6 MB。
- Fixed: `d354f98` 与 `cadf095` 将拖动限位从整块透明画布收敛为当前显示片段的裁剪框，并使用完整屏幕边界，宠物可以贴近上下左右屏幕边缘，锚点不会随之后换姿自动移动。
- Changed: `399fef5` 将每宠固定 60 Hz 计时器改为跟随当前素材原生帧率，避免 12 至 24 FPS 素材产生无效 UI 唤醒。build 5 的 60 Hz 双宠稳定态十次 CPU 取样平均为 2.98%，build 6 的安装后对比仍待 Mac 解锁。
- Review: 最终代码 `cadf095` 的 macOS 运行 `32627927411` 与 Windows 运行 `32627927365` 均成功。build 6 已完成 arm64、严格签名和零素材构建，主程序 SHA-256 为 `5a3b397d4475df3e821f635d2cfca422188a37a396888aeb9e3553214c709d3a`，但锁屏前尚未替换安装。
- Fixed: 对 build 5 的 5 秒进程采样显示，主 RunLoop 上的每次 Timer 回调仍会创建 Swift 并发 `Task` 并重新入队。`cb28c6e` 改为在已确认的 MainActor 上直接执行 tick，不改变计时来源、帧序或速度。
- Review: build 7 取代未安装的 build 6 成为下一候选，arm64、严格签名和零素材检查通过。主程序为 1,210,800 bytes，SHA-256 为 `17b7a5f54dfad0238f92dfba546d76356fecf971c6d69990a3fe36e532616cb2`，安装态 CPU 与视觉对比仍待 Mac 解锁。

## Unreleased · 2026-08-23

- Changed: PetPack 1.0 冻结为普通 ZIP 单文件容器，并把 `cropped-rgba-clips` 作为长期兼容基础表示。五百与飞流先离线转换，首批包只含完整性哈希，不实现官方签名；新 Player 不直接加载旧 schema `0.4.0`。
- Changed: `studio/` 明确为根 Git 忽略且不创建独立 Git 的本机私有目录；dotenv 与生产工具一次性迁入，不保留根目录或 `petsdesk` 旧路径兼容。
- Changed: 重构直接在 `main` 上按验证切片提交并及时 push。失败大型媒体、字节重复文件、可重建缓存和临时产物在生成审计记录后移入系统回收站，不再逐项请求二次确认。
- Changed: 五百与飞流先使用现有批准媒体制作 PetPack 1.0；小葵本轮只整理已有资料，不继续生成、抠图或制作 PetPack。
- Added: 新增 `DIRECTORY.md`，冻结整个项目继续以 `petsgraph/` 为唯一物理根，并定义 `player/`、`petpack/`、`studio/`、`pets/`、`petpacks/`、`codexpets/` 与 `.local/` 的目标职责。
- Changed: “零素材”边界精确为 Player 子树与 Player 发布物不包含真实宠物；根公开 Git 允许在 `codexpets/packages/public/` 保存单独授权的 Codex 宠物图集。
- Changed: Codex 目标目录名确定为 `codexpets/`，公开包、私有包、工作区和清单分开；当前 `codex-pets/`、旧清单和管理工具继续作为 As-built，尚未迁移。
- Added: 目录迁移必须逐切片记录源目标、文件数、字节数、摘要、备份和回读；禁止整体删除 `workspaces/` 或在项目根递归清理 ignored 私有目录。
- Review: 本里程碑只更新目录与 Git 边界文档，没有创建目标目录、移动素材、重命名 Codex 包、修改工具默认路径或改变 Player 构建发布物。

## Unreleased · 2026-08-22

- Changed: 产品定位收敛为宠物离世纪念陪伴。下一代宠物只按各自时钟自主播放连续生活视频，不响应点击，不提供动作或睡姿菜单，窗口不再随步行动作移动。
- Changed: 下一代架构分为开源零素材 PetsGraph Player、私有 PetsGraph Studio 和客户自持 `.petpack`。Seedance 等制作工具、提示词、客户资料和正式宠物素材保持私有。
- Added: PetPack 1.0 目标契约覆盖一包一宠、装载导入、内部 canonical 库、版本更新、长期兼容、固定舞台、独立时钟、完整性与可选来源签名。容器和透明媒体基线仍待小葵双平台原型冻结。
- Changed: Player 支持同时装载多只宠物，每只宠物独立计时、独立位置和独立可见状态，全部宠物共享 `0.5` 至 `2.0` 全局倍率，不做宠物互动或动作协调。
- Changed: 目标菜单固定为装载宠物包、显示宠物、隐藏宠物、卸载宠物、大小和退出。显示、隐藏与卸载均支持“全部”和动态宠物列表；卸载删除内部包，再次使用需要用户保存的原始 `.petpack`。
- Changed: 当前实现范围保持 Apple Silicon macOS 与 Windows x64。iPadOS 与电视端推迟，但 PetPack 1.0 保持平台无关，未来 Player 不应要求客户重新定制。
- Changed: 客户资料按客户和宠物独立私有目录保存，默认不训练、不公开，暂定从最终交付日起保留一年；正式接单前补齐到期处理与授权文本。
- Deprecated: 面向下一代产品的点击坐立、指定睡姿、动作菜单、窗口 root motion、桌面巡游和 Player 内嵌真实宠物素材。历史 `v0.6.0` 发布物与已批准媒体继续保留并作为迁移输入。
- Review: 本里程碑只完成产品与文档决策，没有实现 Player/PetPack 1.0，没有重编五百、飞流或小葵媒体，也没有改变现有 `v0.6.0` Release。

## Unreleased · 2026-08-19

- Added: 在 `codex-pets/` 同时维护五百 `wubai-v0` 与飞流 `feiliu-hatch-native-v1` 两套 Codex v2 自定义宠物。每套包含 `pet.json` 与 1536×2288 RGBA WebP 图集，两张图集合计约 4.4 MB。
- Added: 新增 schema 1 `manifest.json`，固定目录、显示名、字节数和 SHA-256；新增 `tools/manage-codex-pets.py`，校验目录白名单、v2 网格、透明通道、哈希，并提供幂等安装、冲突拒绝和备份后替换。
- Changed: README 与素材授权说明覆盖仓库内 Codex 图集。小型 Codex 导出允许进入 Git，数百 MB PetsGraph 正式运行时媒体继续只随 GitHub Release 分发。
- Review: 两张仓库图集与本机已安装版本逐字节一致，仓库校验器和 Hatch Pet `--require-v2` 均通过。隔离目录完成首次安装、幂等重装、冲突拒绝、备份替换和安装后哈希核对。该机械结论不等于 Codex 动作视觉通过，也不改变 PetsGraph `runtime-chain-approved` 状态。

## v0.6.0 macOS release amendment · 2026-08-18

- Added: v0.6.0 双平台清单新增 `PetsGraph-v0.6.0-macOS-arm64.dmg`，与已经验收的 Windows 11 x64 ZIP 组成精确双附件集合。macOS DMG 为 `857640594` 字节，SHA-256 为 `04c6f30e35d7dd8b5b096d0051aad628987d59b8245d84060cf704f02709b159`。
- Added: macOS v0.6.0 App 使用已经验收的双猫相伴 Logo。内嵌 ICNS SHA-256 为 `8b976a2ebe6badbcd6709201a03dc5900ed45c7bad01d4a210fde8cdbf38c24d`，Bundle 仍为 `PetsGraph` 与 `com.maxwell.petsgraph`。
- Changed: App 版本和宠物内容版本分别记录。macOS App 为 `0.6.0`，继续内嵌已批准的五百与飞流 `0.5.10` 宠物包，不为品牌更新重编或伪造 12,013 帧媒体版本。
- Changed: 已存在的 `v0.6.0` 标签保持指向 `ce4570cef6f47fe75b32df40c1476b0657a1d999`。默认分支承载标签后的双平台发布补充，验证流程要求平台源码相对标签无变化。
- Changed: Windows Runner 在草稿阶段复验 Windows ZIP。macOS Runner 改用 `contents: read`，只在公开后下载双附件并挂载 DMG，不具备创建、编辑或发布 Release 的权限。
- Review: 67 项 XCTest 全部通过。macOS App 与 DMG 在本机通过 `arm64`、Bundle 版本、Logo 哈希、ad-hoc 签名、双宠包、运行时完整性、`hdiutil verify` 和只读挂载校验。
- Review: GitHub Windows 草稿复验 `32139232230` 和公开 macOS 只读复验 `32139688614` 均成功。v0.6.0 已作为最新版公开，远端回读确认不是草稿、不是预发布，两个附件均为 `uploaded`，字节数和服务端 SHA-256 与双平台清单一致。

## v0.6.0 · 2026-08-18

- Added: 发布首个 Windows 11 x64 版本，使用 .NET 10 WPF、self-contained 多文件便携 ZIP、透明置顶窗口、逐像素鼠标穿透、拖动、系统托盘、七档全局缩放、位置持久化和每用户单实例。
- Added: Release 精确只提供 `PetsGraph-v0.6.0-Windows-x64.zip`，不提供 MSIX、安装器、代码签名、Windows 10 或 Windows on Arm 版本。macOS 用户继续使用 v0.5.10 Apple 芯片 DMG。
- Changed: Windows 草稿 Release 验证工作流现在检出精确标签，并按仓库清单复验唯一附件、字节数、SHA-256、版本、AMD64 PE、双宠数量和运行时完整性。
- Changed: 用户明确授权清理 `dist/` 中约 34 GB 的旧 macOS 候选 App 和 4 份废弃 Windows ZIP，当前只保留冻结的 v0.6.0 正式 ZIP。历史正式发布继续由 Git 标签、GitHub Release、仓库清单和批准包保留。
- Review: 7 项 MSTest、WPF 解决方案 0 警告 0 错误、两个包 84 个 clip 与 12,013 帧完整性、本机交叉编译、AMD64 PE、488 个 ZIP 条目和 GitHub Windows Runner 通过。冻结 ZIP 为 `913953281` 字节，SHA-256 为 `90578d6620ef9c221c173b173c24631d6e756b372b532030f8669994d22b0015`。
- Review: 朋友已在真实 Windows 11 x64 电脑上完成使用验收，最终反馈为没有问题，发布所有者明确授权发布 v0.6.0。该反馈没有附带分项时长或 DPI 测试日志，因此不补写未留证的量化结论。
- Fixed: 修复 Windows 草稿 Release 验证工作流无法读取草稿附件的问题。GitHub 对 `contents: read` 工作流 token 返回 `release not found`，经发布所有者明确授权后改为 `contents: write`；工作流仍只执行 Release 查看和下载，不包含发布、删除、覆盖或上传命令。

## Unreleased · 2026-08-18

- Added: 新增只面向 Windows 11 x64 的 .NET 10 WPF 内部宿主。它复用五百和飞流的 schema `0.4.0` 固定裁剪 RGBA 包，提供双宠独立行为、透明置顶窗口、宠物本体点击、DPI 拖动、托盘菜单、睡姿选择、七档全局缩放、位置持久化和每用户单实例。
- Added: 新增 Windows PowerShell 与 macOS 交叉构建脚本、锁定 NuGet 依赖、真实宠物包校验器、Windows Runner 代码运行包工作流和草稿 Release ZIP 只读验证工作流。默认交付 self-contained 便携 ZIP，不生成 MSIX、安装器或代码签名。
- Added: 采用用户确认的双猫图标，生成 1024×1024 RGBA 主图、macOS ICNS 和 Windows ICO，并把图标实际接入两个平台的构建产物。
- Fixed: Windows 渲染层不再把 RGBA 字节误当 BGRA，而是转为 WPF `Pbgra32`。窗口使用与 macOS 相同的 clip 级固定正方形视口，并区分制作画布原点、presentation offset、左右 root motion 与当帧可见内容边界修正，避免宽画布、原地滑动和位置持久化跳变。
- Changed: Windows `v0.6` 只接受当前已嵌入媒体的 environment props。尚未实现的 persistent 或 node-scenes 独立道具会被显式拒绝，不会静默忽略。
- Review: macOS arm64 上的 .NET SDK `10.0.400` 交叉编译通过，7 项 MSTest 通过，WPF 解决方案 0 警告、0 错误，两个正式包共 84 个 clip、12,013 帧通过完整性和渲染校验。最终 ZIP 为 `913953281` 字节，SHA-256 为 `90578d6620ef9c221c173b173c24631d6e756b372b532030f8669994d22b0015`。GitHub Actions `32114691048` 完成锁定还原、测试、WPF 编译、self-contained 发布、AMD64 PE、ZIP 结构和 artifact 校验。真实 Windows 11 GUI 人工闸门尚未完成，因此本次不创建 Windows GitHub Release。

## v0.5.10 · 2026-08-18

- Added: 发布 PetsGraph `0.5.10` 双宠正式版，同时内嵌五百与飞流。两只宠物拥有独立动作会话、随机时钟、位置和中文睡姿菜单，首次安装默认在屏幕左下角横排。
- Changed: 用户界面中的宠物名统一使用不带姓氏的短名，当前为“五百”和“飞流”。
- Changed: 飞流最终 `baseHeightPt` 定为 `181.125`，五百为 `172.5`，即同倍率下飞流比五百大 5%。该调整只改变包级显示基准，不修改运行时媒体。
- Fixed: 修复飞流猫窝右侧过度抠图造成的缺口，只恢复猫窝缺失像素，不改变猫、动作帧、相对位置或时间。
- Changed: 新版本 GitHub Release 精确只提供一个 Apple 芯片 DMG，不再提供 App ZIP、预览图、校验和附件或独立宠物包。
- Review: 67 项 XCTest 全部通过。两个正式包共 84 个 clip 与 12,013 帧，结构、动作图、完整性、全部媒体、arm64 架构、ad-hoc 签名和 DMG 均通过校验。Maxwell 已确认双宠真实桌面布局、菜单、拖动、缩放、独立随机、猫窝路径、透明边缘与最终相对体型“通过”，两个包均为 `runtime-chain-approved` 和 `installable=true`。

- Added: 飞流精抠动作图已编译为 `feiliu-quiet-companion-0.5.0-preview.2` 运行时候选包，包含 31 个 clip、5,147 帧、11 个节点和 20 条有向边。逐 clip 保留人工定稿的 12、16.2、18 或 24 FPS，全部 root motion 为零。`preview.2` 只把包级显示基准从 150 pt 调整为 172.5 pt，不修改素材帧。
- Added: 单个 PetsGraph 进程可以同时装载五百和飞流。每只宠物拥有独立窗口、动作会话、随机时钟、位置和中文睡姿菜单，App 共享一个 24 Hz scheduler。
- Added: 首次安装默认装载全部宠物，并在物理屏幕左下角按五百、飞流顺序横排。已装载宠物集合、每只宠物位置和全局显示倍率会分别持久化。
- Added: 菜单提供 `0.5×`、`0.75×`、`1.0×`、`1.25×`、`1.5×`、`1.75×`、`2.0×` 七档全局显示倍率。调整会立即作用于全部已装载宠物，同时保持各自地面锚点和当前动作。
- Changed: scene 目录由宠物包数据声明，加载器不再写死 `floor`、`pillow` 或 `cat-bed`。构建器支持重复传入 `--package`，并拒绝重复宠物 ID。
- Fixed: 透明窗口不再沿用超宽制作画布。每条 clip 以整段 alpha 并集生成固定正方形视口，提示框按文字和可见主体收紧，首次横排按正方形窗口边界紧凑排列；位置存储迁移到逻辑制作画布原点，避免旧宽窗口坐标污染新布局。
- Changed: 飞流 `preview.3` 把 `preview.2` 的桌面显示基准从 172.5 pt 精确放大 10% 到 189.75 pt。31 个运行时媒体文件与 `preview.2` 逐字节一致。
- Fixed: 水平边界限制改为使用当帧可见主体边界，宽过渡的透明方窗超出屏幕时不再额外平移宠物。行为中心改用当帧 ground anchor，不再使用宽方窗中心。
- Review: 后续回归增至 65 项 XCTest，0 失败。`candidate.4` 为 arm64，ad-hoc 签名通过，仍待 Maxwell 真实桌面验收。
- Review: 63 项 XCTest 全部通过。双宠候选静态校验覆盖 84 个 clip 和 12,013 帧，App 为 ad-hoc 签名的 Apple 芯片 `0.5.0` 候选。真实桌面首次布局、菜单、拖动、倍率、独立随机时钟和双宠资源占用仍待 Maxwell 人工验收，因此不得标记为 `runtime-chain-approved`、`installable=true` 或公开 Release。

## Unreleased · 2026-08-17

- Added: 飞流当前素材动作图完成 11 个节点、20 条有向边和 31 个唯一素材的完整精抠整链，Maxwell 人工结论为“通过”。
- Changed: 恢复 `rest.floor.semi-supine.right`，仰躺睡改为经半仰睡往返；继续排除睡眠香箱与收爪趴睡。飞流当前共有 9 个自主睡姿和 2 个交互坐姿。
- Changed: 12 条需要改进的地面素材完成选择性精抠，19 条已经干净的素材逐字节复用。精抠没有改变已通过的整段缩放、平移、帧序或批准播放速度。
- Review: 本次批准范围是素材动作图与精抠整链。飞流宠物包、随机运行时、真实桌面点击拖动、资源测量和 `installable=true` 仍待后续验收。

## Unreleased · 2026-08-13

- Changed: 2026-08-15 飞流首版动作图简化为 8 个自主睡姿和 2 个交互坐姿。废弃收爪趴睡、半仰睡和猫窝坐姿作为场景进出网关的旧流程，猫窝场景改为平趴睡直接往返猫窝蜷睡，猫窝蜷睡再往返猫窝坐姿和其他猫窝睡姿。
- Changed: 飞流猫窝正面坐姿的私有素材契约统一使用正式节点 ID `sit.front.cat-bed`，不再保留 `rest.cat-bed.sit-front` 同义节点。
- Added: 动作契约新增经过人工完整验收的同节点偶发自环倒序例外。普通姿态转换和场景边仍禁止倒放，参见 ADR-032。

## v0.10.0-feiliu-cat-bed-direction · 2026-08-13

- Added: 飞流猫窝场景冻结五张人工通过静态端点，包括正面坐姿、蜷睡、自然趴睡、侧伸睡和舒展露腹睡。
- Added: 建立猫窝静态端点统一坐标契约。编译副本按猫窝宽度和底部中心对齐到 2496×1664，再嵌入 960×960 生成安全画布，猫窝锚点为 `(480, 840)`；运行时 480×480 预览锚点对应 `(240, 420)`。
- Changed: 飞流首版从无道具加毛毯调整为 6 个无道具睡姿加 4 个猫窝睡姿。`sit.front.cat-bed` 是非随机交互网关，`rest.cat-bed.curled` 是猫窝随机睡姿枢纽。
- Changed: 历史毛毯和毛毯踩奶素材继续完整保留，但不进入飞流首版包。未来踩奶需要以猫窝场景重新设计和独立验收。
- Review: 本次只完成静态端点审计、编译副本和产品文档。没有调用 Seedance，没有批准循环、过渡、抠图、完整动作图、运行时链或可安装包。

## v0.9.0-feiliu-custom-direction · 2026-08-12

- Added: 飞流定制动作图加入毛毯场景正面坐姿 `sit.front.blanket`，作为毛毯点击目标、场景进出和路径汇合节点，不进入自主睡姿随机池。
- Added: 制作侧登记 `gpt-image-2` 静态生成与编辑能力，只记录 `GPT_IMAGE_API_KEY`、`GPT_IMAGE_MODEL`、`GPT_IMAGE_GENERATIONS_URL` 和 `GPT_IMAGE_EDITS_URL` 变量名，不记录值。
- Changed: 素材路线从面向任意用户的通用生成 Skill 收敛为 Maxwell 自有宠物与朋友明确委托宠物的人工定制。底层 provider、账本、抠图、完整性和打包工具继续复用，不要求姿势和动作图跨宠物一致。
- Changed: 正式随机行为定义为合法动作图上的加权随机游走，使用长尾停留、近期姿势去重、场景粘性、节点权重和活动冷却。串行完整链只用于素材 QA，不作为正式轮播顺序。
- Changed: 飞流采用地面与毛毯两个睡眠子图。平趴睡和毛毯蜷睡分别作为图枢纽，毛毯踩奶作为带冷却的偶发活动。
- Review: 本次只更新产品、数据契约和制作边界，没有调用 provider、修改批准素材、接入飞流运行时或生成可安装包。飞流毛毯坐姿、剩余过渡、随机行为、完整桌面链仍需分别验收。

## v0.8.0-public-low-power · 2026-08-10

- Added: 发布 PetsGraph App `0.4.0`，正式内嵌 schema `0.4.0`、`cropped-rgba-clips` 的李五百低功耗宠物包。正式包含 53 个 clip、6,866 帧、113 条完整性记录和 1.827 GB raw 媒体。
- Added: 低功耗编译器新增显式 `--release-approved` 晋级路径，只接受 `runtime-chain-approved`、`installable=true` 的来源包和正式语义版本。默认构建继续保持候选状态。
- Changed: 发布构建器拒绝 App 与内嵌宠物包版本不一致、未整链批准或不可安装的输入。GitHub Actions 额外核对 schema `0.4.0`、`cropped-rgba-clips`、批准状态、剩余闸门和精确四附件集合。
- Changed: v0.3.1 已批准 PNG 包继续作为不可变制作事实源和公开回滚基线。v0.4.0 不重新生成、抠图、补帧、逐帧定位或修改获批帧。
- Fixed: 正式 GUI 使用每用户单实例锁，重复启动在加载 1.827 GB 媒体前退出，减少两只宠物叠加和资源重复占用。
- Review: 本机 57 项 XCTest 全部通过；53 个 clip 与 6,866 帧运行时媒体、arm64 架构、ad-hoc 签名、ZIP、DMG 和四附件 SHA-256 全部校验通过。DMG 为 574,621,053 字节，约 548 MiB。普通睡眠约 1.3% 到 1.6% CPU 与 53 MiB physical footprint，连续换姿约 2.1% 到 2.7% CPU 与 19 到 46 MiB。Maxwell 明确授权发布 v0.4.0。

## v0.7.0-low-power-candidate · 2026-08-10

- Added: 新增 schema `0.4.0` 的 `cropped-rgba-clips` 媒体契约与编译器。它从完整性已验证的 PNG 包确定性生成每 clip 固定 alpha 并集裁剪、预乘 RGBA 连续帧流、来源清单和新完整性清单，不覆盖或修改批准 PNG。
- Added: AppKit 运行时新增只读内存映射、Core Graphics provider 直接寻址、完整画布 crop 布局、raw alpha 命中、小循环整段预建、长过渡有界分块，以及 HEVC Alpha 对照实验加载能力。
- Added: GUI 使用每用户单实例锁，重复启动在加载媒体前立即退出。新增 raw 媒体缺失、篡改、异常隐藏、字节契约、元数据哈希和单实例锁测试。
- Changed: 主播放时钟保持 24 Hz，只在 clip、帧、镜像或位置实际变化时提交新画面。透明窗口改为直接 CALayer 内容提交，发布构建清理签名干扰 xattr，`dist/` 不进入 Git 历史。
- Changed: 原始 PNG 包继续作为制作事实源和 v0.3.1 正式回滚基线。完整 raw 候选包含 53 个 clip、6,866 帧与 1.827 GB 媒体，评审状态保持 `cropped-rgba-awaiting-human-runtime-review`、`installable=false`。
- Deprecated: 把 HEVC 文件体积缩小直接等同于低 CPU；逐帧 `CIImage → CGImage → NSImage` 重建；同时使用 LaunchServices 与直接执行启动 QA；把旧 AppTranslocation 资源占用归因给当前候选。
- Review: 完整 Xcode 真实执行 57 项 XCTest，0 失败。完整候选通过包完整性和全部 6,866 帧可读校验；真实桌面多段普通睡姿随机链、安全预加载和单实例回归通过。普通睡眠约 1.3% 到 1.6% CPU、53 MiB，连续换姿约 2.1% 到 2.7% CPU、19 到 46 MiB。完整睡姿、点击拖动、锁屏恢复和长时间视觉验收尚未重跑，因此不替换 v0.3.1 Release。

## v0.6.0-generic-runtime · 2026-08-10

- Added: 发布通用 `PetsGraph` App `0.3.1`，Bundle ID 为 `com.maxwell.petsgraph`。菜单从内嵌宠物包读取名称并显示「当前宠物：李五百」，通用运行时反馈不再写死具体宠物名。
- Added: 发布构建器原子生成 DMG、备用 App ZIP、睡姿总览和校验和。GitHub Actions 验证精确四附件集合、字节数、SHA-256、App 名称、Bundle ID、版本、最低系统、`arm64` 架构、签名和内嵌宠物包完整性后才发布草稿。
- Changed: App、DMG 和 ZIP 统一使用 PetsGraph 名称。`0.3.1` 的全部批准帧与 `0.3.0` 逐项哈希一致，没有重新生成、抠图或修改源帧。
- Changed: README、安装说明、发布说明和 AIREADME 更新为通用运行时与当前宠物分层，并记录约 465 MB 透明 PNG 是当前包体积的主要来源。
- Removed: Release 不再重复上传独立 `.petsgraph-pet`，普通用户只需下载 DMG。
- Deprecated: 把某只宠物名称固化为 App 品牌、Bundle 身份或通用反馈，以及用宽松附件集合发布草稿。
- Review: 完整 Xcode 真实执行 45 项 XCTest，0 失败。正式包加载 53 个 clip、10 个可自主停留节点、90 条换姿路径、10 条醒来路径、10 条返回路径和 6,925 条完整性记录。Apple 芯片 App、ZIP 解包、DMG 挂载、ad-hoc 签名和内嵌包校验通过。

## v0.5.0-public-alpha · 2026-08-10

- Added: 李五百睡觉陪伴 App `0.3.0` 新增「选择睡姿」中文菜单，列出 7 种普通睡姿和 3 种枕头睡姿。节点契约增加 `displayName`，正式菜单、状态和操作反馈不再显示内部动作 ID。
- Added: 指定睡姿复用完整动作图。睡眠中立即规划，坐姿先自然返回，不可中断过渡期间只保留最后一个目标。增加睡眠中选择、连续选择、坐姿选择、中文名称和缺失名称拒绝测试。
- Added: 新增 Apple 芯片 DMG、App ZIP、素材包 ZIP、睡姿总览、SHA-256 文件、发布清单、安装说明和 GitHub Actions 验证发布链。
- Changed: 首个公开版只支持 `arm64` 和 macOS 14 及以上。正式媒体允许随 GitHub Release 公开，原始照片、生成任务、失败候选和私有生产上下文继续保留在受控工作区。
- Changed: `0.3.0` 的 53 个 clip、14 个节点、39 条边与 `0.2.0` 的全部获批帧逐项哈希一致，不重新生成、抠图或修改源帧。
- Removed: Intel 和通用二进制不进入首个公开版本。
- Deprecated: 在正式 UI 显示 `sit-front-loop` 等内部名称，把数百 MB 正式媒体写入 Git 历史，以及未核验草稿附件就直接公开。
- Review: 完整 Xcode 运行 45 项 XCTest，0 失败。正式包验证 10 个自主睡姿、90 条换姿路径、10 条醒来路径、10 条返回路径和 6,925 条完整性记录。App 真实启动成功，系统状态栏菜单树因辅助功能边界未能由自动化工具完整展开，因此该项依靠契约测试和朋友实际安装继续观察。App 使用 ad-hoc 签名，没有 Developer ID 和 Apple 公证。

## v0.4.0-mvp · 2026-08-10

- Added: 完成李五百睡觉陪伴 `0.2.0` 数据契约、行为规划器、点击状态机、普通与枕头睡眠图、版本化 `.petsgraph-pet` 和可双击 macOS `.app`。正式包包含 53 个 clip、14 个节点、39 条边与 6,925 条完整性记录。
- Added: 新增随机长尾停留、近期去重、枕头场景粘性、网关和交互节点排除、安全退出、下一边与目标循环预加载、点击去抖、不可中断过渡、猫体命中和严格零场景内 root motion。
- Added: 新增素材生产、固定画布、道具、严格边 QA、周期审计、私有配置编译和版本化 App 构建工具。所有 provider 任务、失败候选和批准证据继续留在被 Git 忽略的私有工作区。
- Changed: 安静陪伴首次显示默认放在物理屏幕左下角，窗口位于普通窗口和 Dock 前方；用户可改变全桌面 x 和 y，宠物自主睡眠只保持或水平改变位置。
- Changed: 获批 preview.10 通过帧哈希完全一致的正式重编译晋级为 `wubai-quiet-companion-0.2.0`。只改变包身份、批准状态和完整性清单，不重新生成、抠图或修改源帧。
- Fixed: 修复高频点击反转醒来过渡、默认模式误接收桌面目的地点击、窗口拖动垂直范围受限、Dock 前方层级不足、左下角仍保留工作区安全边距，以及素材缓存长期占用等运行时问题。
- Removed: 无。走路、跑步、左右原生素材和工程行为测试继续保留，但不进入安静陪伴默认行为。
- Deprecated: 把 engineering preview、全局桌面点击、强制走跑或镜像候选当作首发默认体验。
- Review: 完整 Xcode 运行 41 项 XCTest，0 失败。正式包加载、哈希、hidden 标记、内嵌包一致性和 ad-hoc 签名校验通过。真实桌面观察 30 分 36 秒，并完成正常速度、二倍慢放、点击、全桌面拖动、Dock、Space 和锁屏恢复验收。Maxwell 最终结论为“通过”，批准索引更新为 `runtime-chain-approved` 和 `installable=true`。当前仅为本地安装版本，尚未 Apple 公证或公开发行。

## v0.3.0-direction · 2026-08-10

- Added: 定义「李五百睡觉陪伴 MVP」作为第一款产品，包含默认睡眠、随机时间换姿、点击睡眠与正面坐姿往返、全桌面拖动、置顶和枕头核心场景。
- Added: 素材包草案新增 `behavior.json`、节点 `scene`、`role`、`autonomousEligible`、道具集合、宠物命中区与猫道具联合屏幕边界契约。
- Changed: 首发闸门从完整走跑闭环改为普通睡眠与枕头睡眠完整动作图、点击响应、道具连续和 30 分钟真实桌面运行。
- Changed: 现有靠枕 B 改为 `pillow.gateway.leaning.right` 的候选语义。它不参与随机睡姿，先验证短循环和真实桌面接缝，失败后才生成 B2。
- Changed: 核心素材取消固定三次尝试上限。用户明确授权后允许多次受控生成，每次必须改变明确假设并完整保留生产履历。
- Removed: 无。已批准走路、跑步、左右移动和 root motion 素材全部保留。
- Deprecated: 点击桌面目的地移动、自主走跑、全局桌面点击监听和强制走跑菜单作为首发默认行为。工程入口可以保留用于历史验证，但不能进入正式睡眠 MVP。
- Review: 本版本只更新产品意图、目标契约和文档路由。`bash tools/test-swift.sh` 真实执行当前工程实现的 25 项 XCTest，0 失败，但新增 `0.2.0` 睡眠行为字段尚未实现。当前代码工作树仍包含工程行为预览，枕头素材仍有未分段或未完成回程的路径，新的睡眠 MVP 包尚未构建，整体保持 `installable=false`。

## v0.2.3-runtime-safety · 2026-08-09

- Added: 新增左侧伸展到仰卧、仰卧返回左侧伸展两条已批准有向边的 0.2.0 聚焦预览包，复用两个现有循环。该包包含 15 个片段、7 个节点、8 条边和 1,145 个完整性条目，正常速度与 2 倍慢放真实桌面链已经录制。
- Added: `sit.front ↔ rest.prone.left` 两条桥接边均已完成素材级人工验收并进入五百私有批准索引。当前索引共有 9 个循环动作和 18 条有向边。
- Added: XCTest 增加新睡姿图契约、逐帧顺序、预加载和不安全循环退出的回归覆盖，完整 Xcode 下共 13 项测试通过。
- Changed: 原型编译器可以固定并验证 `approvedRecipeSha256`，同时核对主体 ID、批准状态、事实源路径、批准帧数、FPS 和序列摘要。运行时 clip 履历保留该配方哈希。
- Fixed: 加载器现在拒绝从非安全帧离开循环、截断或重复过渡、以及入口出口姿态不兼容的预览序列，防止评审链绕过正式动作图约束。
- Removed: 无。
- Deprecated: 仅凭批准配方路径名信任输入，以及用任意演示片段顺序代替动作图安全退出检查的做法。
- Review: 新增左侧伸展与仰卧链只完成素材级验收、机械校验和真实桌面录制，仍等待 Maxwell 的运行时视觉结论。坐趴桥接尚未进入完整连通包，整体状态保持 `partial-runtime-chain-approved` 和 `installable=false`。

## v0.2.2-materials · 2026-08-09

- Added: 新增正面坐姿循环、右向站立到正面坐姿、正面坐姿到右向行走，共三个已人工通过并固化生产履历的素材单元。`sit.front` 作为方向中立稳定节点，坐到行走边在前腿向右迈步时建立行走意图。
- Added: 新增左侧蜷卧到仰卧、仰卧循环、仰卧返回左侧蜷卧，以及此前批准的趴卧与香箱双向闭环。五百私有批准索引当前共有 8 个循环动作和 12 条有向边。
- Changed: 坐到右向行走保留 provider 终端帧作为已批准走路第 22 相位，再从循环第 23 相位继续，不再套用统一排除终端帧的规则。
- Fixed: 坐到右向行走前两次候选的画布触边问题未通过后处理掩盖，最终通过版本保留非零四侧边距。拒绝候选继续留在私有工作区，不进入批准索引。
- Removed: 无。
- Deprecated: 为正面坐姿复制左右节点，以及不检查目标循环相位就统一删除 provider 终端帧的做法。
- Review: 本里程碑只表示素材级人工通过。新增坐姿、香箱和仰卧尚未编入最新运行时包；坐到右向行走的 root motion、移动与休息分量的双向桥接及完整连通运行时链仍未通过，完整包保持 `installable=false`。

## v0.2.1-preview · 2026-08-09

- Added: 新增 0.1.1 带版本号预览包，把用户对睡眠桌面链的明确通过结论写入包内评审索引、宠物批准资产索引和私有运行时记录。
- Changed: `wubai-sleep-closed-chain-v0.1` 从 `awaiting-human-runtime-review` 升级为 `runtime-chain-approved`。完整合并包状态更新为 `partial-runtime-chain-approved`，仍明确 `installable=false`。
- Fixed: 无。
- Removed: 无。
- Deprecated: 无。

- Review: 用户在 150 pt 真实 macOS 桌面窗口中通过趴卧循环、趴卧到侧躺、侧躺循环、侧躺到趴卧和返回趴卧的完整链。0.1.1 与实际观看的 0.1.0 有 798 个运行时文件逐字节一致，只改变版本、评审记录和完整性清单。移动与睡眠之间仍缺少批准桥接动作。

## v0.2.0-preview · 2026-08-09

- Added: 接入已人工通过的趴卧循环、趴卧到侧躺、侧躺循环和侧躺到趴卧，共四个睡眠 clip、两个姿态节点和两条有向边。新合并预览包包含 11 个 clip、5 个节点、6 条边与 800 个完整性条目。
- Added: 新增 XCTest 睡眠包 fixture 与回归测试，覆盖四个 clip、节点边解析、安全退出帧 15 和 52、直接操控中断策略、前瞻预加载、严格零 root motion，以及缺失、篡改和 hidden clip 失败路径。完整 Xcode 下共 10 项测试通过。
- Changed: 睡眠四段编译副本统一固定平移 `(0,+92)` 源像素，把已批准睡眠地面 `y=440` 对齐到全包源地面 `y=532`，运行时地面为 `y=266`。源帧、帧顺序、帧数和动作内部相对位置不变。
- Changed: 用户接受 30 pt/s 的走路窗口速度，跑步保持 115 pt/s。该结论只覆盖走路速度，不自动升级整包状态。
- Fixed: 临时构建目录不再使用点号前缀，并在安装前后检查 `UF_HIDDEN`。加载器按动作图显式寻址，并拒绝 hidden、缺失、被修改、符号链接或缺少完整性条目的必需文件。
- Removed: 无。
- Deprecated: 裸用当前 CommandLineTools 运行测试，以及依赖目录枚举或用户手动 `chflags` 修复包内容的方式。
- Review: 睡眠素材切分已通过人工验收，新桌面预览包完整性和机械约束通过，当前正在等待 Maxwell 的真实桌面链路结论。移动与睡眠之间仍没有批准桥接边，包不可安装。

## v0.1.1 · 2026-08-09

- Added: 新增动作图引用解析测试，核心测试总数增加到 5 个。
- Changed: 宠物包加载器不再枚举 `clips/` 目录，而是从动作图节点的 `loopClip` 与有向边的 `clip` 推导必需片段，并按 `clips/<clip-id>.json` 显式寻址。
- Fixed: 修复 macOS Desktop File Provider 路径中目录枚举偶发漏掉已存在片段，导致完整包被误判为缺动作的问题。当前 30 pt/s 候选与已拒绝的 48 pt/s 历史包都可读取 7 个片段并通过 519 文件完整性校验。
- Removed: 无。
- Deprecated: 以目录枚举结果决定动作集合的加载方式。
- Review: 本修复只改变素材包寻址和校验，不改变画面、root motion 或速度。30 pt/s 版本仍等待用户真实桌面视觉验收。

## v0.1.0 · 2026-08-09

- Added: 首个 Swift Package，包含宠物包路径与 SHA-256 校验、动作图模型、循环相位旋转、逐帧累计 root motion 时间轴、透明 AppKit 窗口和菜单栏预览入口。
- Added: 五百右向私有原型包编译器，将七个已通过单元编译为 320px PNG、帧时长、内容边界、锚点、碰撞区、终点累计位移、图结构、评审状态和 519 文件完整性清单。
- Added: 4 个核心测试覆盖掉帧后直接采样、旋转循环 delta 保真、局部循环在批准相位退出，以及跑步平均速度高于走路两倍。
- Changed: 走跑相关循环和边统一确定性放大约 1.0271，以匹配站走与停步使用的宠物级全局画布基准。该变换后的真实整链仍需人工验收。
- Changed: 首个 48 pt/s 走路候选被用户判定过快。第二版降为 30 pt/s，跑步保持 115 pt/s，起步、加速、减速和停步的逐帧累计轨迹同步重算。
- Fixed: 运行时按动作边声明的入口与出口相位播放局部循环，不在减速后多播或倒退一个步态相位。
- Removed: 无。
- Deprecated: 把 petsdesk 通用模拟速度直接当作五百 root motion 标准的做法。
- Review: 私有包完整性校验与整链日志均通过，窗口从站立到最终站立连续移动。第二版仍等待用户真实桌面视觉结论，状态为 `awaiting-human-runtime-review`，不可安装。

## v0.0.10 · 2026-08-09

- Added: 五百 `walk-right-to-stand-right` 使用完全相同的走路第 22 帧和站立第 0 帧端点，同时提交两个受控候选。v1 测试完成一个末步后收拢站稳，v2 测试直接支撑制动，两项任务各自记录且自动重试均为 0。
- Added: 为 v1 新增 `approved-recipe.json`，记录并行批次、两项任务、提示词与输入哈希、连续第 0 至 95 帧、相邻已批准规范化帧复用、处理脚本、PNG 事实源摘要、输出哈希、图接口和用户选择。五百批准资产目录同步加入该停步边。
- Changed: 用户同时观看左侧 v1、右侧 v2 的正常速度完整动作链和 4 倍慢放后选择 v1。`walk-right-to-stand-right` v1 升级为 `human-edge-approved`，v2 保留并标记为并排评审后未选。
- Changed: 五百右向素材链的三个循环动作和四条必要有向边均已通过人工视觉验收，七个通过单元均有生产履历。素材层闭环完成，下一闸口只剩逐帧 root motion、原生窗口位移同步和真实运行时整链验收。
- Fixed: 无。
- Removed: 无。
- Deprecated: 无。
- Review: v1 外圈 8px 的 alpha 最大值为 0，最小左右边距为 48px 和 68px。素材通过不代表可安装，root motion 和真实窗口同步尚未实现与验收，整体仍为 `not-yet-approved`。

## v0.0.9 · 2026-08-09

- Added: 五百 `run-right-to-walk-right` 使用完全相同的跑步第 33 帧和走路第 23 帧端点，同时提交两个受控候选。v1 测试渐进减速，v2 测试单次明确制动后延长稳定走路区间，两项任务各自记录且自动重试均为 0。
- Added: 为 v2 新增 `approved-recipe.json`，记录并行批次、两项任务、受控差异、提示词与输入哈希、连续第 0 至 95 帧、处理脚本、PNG 事实源摘要、输出哈希、图接口和用户选择。五百批准资产目录同步加入该减速边。
- Changed: 用户同时观看左侧 v1、右侧 v2 的正常速度完整动作链和 4 倍慢放后选择 v2。`run-right-to-walk-right` v2 升级为 `human-edge-approved`，v1 保留并标记为并排评审后未选。
- Changed: 同一高风险动作生产单元允许并行提交最多两个受控候选，但每个候选仍计入三次止损门，且必须共享端点并分别声明唯一假设。不同宠物不得在首只宠物真实窗口链通过前批量展开，见 ADR-011。
- Fixed: 无。
- Removed: 无。
- Deprecated: 无。
- Review: v2 外圈 8px 的 alpha 最大值为 0，最小左右边距为 38px 和 52px，逐帧最大变化低于 v1；用户选择 v2 后，右向走跑双向边均已通过。当前仍缺少 `walk-right-to-stand-right`、逐帧 root motion 和真实窗口同步，整体不可安装。

## v0.0.8 · 2026-08-09

- Added: 五百 `walk-right-to-run-right` 第 1 次受控生成，使用已通过走路第 23 帧和跑步第 33 帧作为严格首尾端点，并将两侧素材规范化到 480px 参考宽度、统一水平中心和地面基线。
- Added: 从 97 帧母片直接采用第 0 至 95 帧形成 4 秒加速边，排除 provider 终端第 96 帧，再由运行时进入跑步第 33 帧并继续第 34 帧。新增正常速度走路到加速到跑步整链和 4 倍慢放。
- Added: 新增该图边的 `approved-recipe.json`，记录唯一生成任务、端点相位选择、规范化变换、提示词与输入哈希、处理脚本、PNG 事实源摘要、输出哈希、图接口和用户结论。
- Changed: 用户通过正常速度整链与慢放后，`walk-right-to-run-right` 升级为 `human-edge-approved`，五百私有批准目录同步增加该图边。
- Fixed: 无。
- Removed: 无。
- Deprecated: 无。
- Review: 生成边外圈 8px 的 alpha 最大值为 0，但最小左右边距为 10px 和 32px，低于提示词目标 48px。用户已在完整链和慢放中接受该偏差。减速边、停步边、逐帧 root motion 和真实窗口移动仍未批准，当前不可安装。

## v0.0.7 · 2026-08-09

- Added: 五百 `run-right-loop` 第 3 次候选使用同一已通过跑步相位作为严格首尾帧，Seedance 2.0 完整版生成 121 帧母片，并从中选择连续 40 帧形成 1.666667 秒、24 fps 跑步循环。
- Added: 新增该动作的 `approved-recipe.json`，记录两次未创建任务的参数校验、唯一实际生成任务、seed、输入与提示词哈希、连续选帧、抠图和分析脚本哈希、PNG 事实源摘要、评审证据与剩余闸门。
- Changed: 用户观看正常速度三轮循环和 4 倍慢放后明确通过，`run-right-loop` 升级为 `human-action-approved`，五百私有批准目录同步增加该动作。
- Fixed: 首版青幕通道放大会把视频压缩产生的青色背景波动误判为透明主体，改为边界中位青色归一化、颜色距离主体保留、alpha 下限与前景去污染的混合处理。
- Removed: 无。
- Deprecated: 在严格同首尾帧模式下同时提交参考图片或参考视频的组合。当前 Seedance 接口会在任务创建前拒绝该参数组合。
- Review: 跑步循环外圈 8px 的 alpha 最大值为 0，选段端点主体中心差为 0，用户已通过动作本身。加速边、减速边、逐帧 root motion 和真实窗口快移尚未验收，当前不可安装。

## v0.0.6 · 2026-08-09

- Added: 为五百已通过的 `walk-right-loop`、`stand-right-loop` 和 `stand-right-to-walk-right` 分别建立 `approved-recipe.json`，并新增宠物级 `approved-assets.json` 汇总目录。
- Added: 生产履历记录 provider、模型、任务、提示词和输入哈希、生成参数、母片、连续选帧、处理约束、PNG 事实源摘要、输出哈希、图入口与出口、人工结论、已知取舍和可复用方法。
- Changed: 用户通过第 4 次正常速度整链后，`stand-right-to-walk-right` 升级为 `human-edge-approved`；原本暂定的 `stand-right-loop` 通过相邻出边验证，升级为 `human-action-approved`。
- Changed: 正式约定从本版本起，素材缺少完整生产履历、确定性处理脚本哈希或人工批准证据时，不得进入动作或图边批准状态。
- Fixed: 修正站立动作记录指向第 4 次整链验收视频的相对路径。
- Removed: 无。
- Deprecated: 只保存最终媒体、只保存提示词，或把生成方法留在聊天和临时命令历史中的做法。
- Review: 三个已通过单元均已进入私有履历目录。首个走路循环早于该契约，精确的一次性抠图脚本未保留，已明确记录为历史限制；其输入、提示词、母片、连续帧范围、PNG 事实源、处理方法和输出哈希仍完整保留。右向运行时整链尚未批准，当前不可安装。

## v0.0.5 · 2026-08-09

- Added: 五百 `stand-right-to-walk-right` 第 4 次生成。与前三次不同，本次把生成单元缩小为“站立准备加一次起步”，并从已批准 `walk-right-loop` 的第 22 帧进入循环，后续仍按原顺序播放第 23 帧。
- Added: 第 22 帧纯青尾端锚点、旋转但不改变原帧顺序的走路循环、完整深色整链，以及第 3 次与第 4 次的同步并排视频。
- Changed: 第 3 次经用户确认仍有同样后脚滑步，状态更新为 `not-selected-hind-leg-slide-persists`。第 4 次保持模型、时长、首帧、画布尺度和自动重试为 0，只改变动作分解与尾帧入口相位。
- Fixed: 无。第 4 次模型拉长了站立并减少了过渡内步数，但没有严格遵守单一肢体周期，是否消除后脚滑步仍需用户观看正常速度整链。
- Removed: 无。
- Deprecated: 继续通过提示词强化同一个多步过渡单元的路线。若第 4 次仍不通过，应进一步拆分动作或改变模型策略。
- Review: 第 4 次外圈 8px 无主体，左右最小边距为 38px 和 52px，两个边界均未触碰。新第 22 帧入口姿态连续，但整体中心步幅比第 3 次更大，需要人工确认。

## v0.0.4 · 2026-08-09

- Added: 五百 `stand-right-to-walk-right` 第 3 次受控生成，输入端点与第 2 次哈希完全相同，只加强起步边 1.4 到 2.7 秒的后脚抬起、前摆、落地、承重和离地约束。
- Added: 第 2 次与第 3 次全链并排视频、后腿重点区间并排视频，以及第 3 次逐帧透明边界、中心漂移和两处衔接检查。
- Changed: 第 2 次按用户意见保留，但标记为 `retained-candidate-with-known-hind-leg-slide`；第 3 次标记为 `awaiting-user-comparison-with-attempt2`。
- Fixed: 第 3 次接触表中的后脚抬起与落地阶段更易区分，画面内水平中心范围从第 2 次的 40px 缩小到 33px。该机械变化不代表用户已确认滑步消失。
- Removed: 无。
- Deprecated: 相同端点、模型和生成单元的继续抽取在第 3 次后停止。若第 3 次仍不通过，必须改变生成单元、约束方式或模型策略。
- Review: 第 3 次外圈 8px 无主体，左右最小边距为 22px 和 60px；尾巴未触边，但左侧余量比第 2 次更小。最终选择等待用户观看并排视频后决定。

## v0.0.3 · 2026-08-09

- Added: 五百 `stand-right-to-walk-right` 第 2 次受控生成，首尾端点缩放到 88%，使用纯青背景和明确安全包络，并把尾帧直接绑定到已批准 `walk-right-loop` 的第 0 帧。
- Added: 97 帧透明外圈检查、逐帧四侧边距与中心漂移报告，以及“站立循环到起步边到三轮走路循环”的深色与青色真实链路预览。
- Changed: 第 2 次只提交一个 Seedance 2.0 完整版任务，时长、分辨率、方向、动作时序和自动重试为 0 的约束不变。
- Fixed: 第 1 次中的尾巴左侧裁切已消失。第 2 次尾巴最小左边距为 58px，外圈 8px 全程没有主体 alpha。
- Removed: 无。
- Deprecated: 无。
- Review: 机械检查认为值得人工评审。右侧最小边距为 32px，低于提示词目标 48px；画面内主体水平中心范围为 40px。当前状态为 `awaiting-user-visual-acceptance`，机械结果不等于用户通过。

## v0.0.2 · 2026-08-09

- Added: 五百 `stand-right-loop` 单动作候选，使用 Seedance 2.0 完整版多参考生视频，从母片直接选择连续 57 帧形成 2.375 秒、24 fps 站立循环。
- Added: 五百 `stand-right-to-walk-right` 第 1 次首尾帧受控生成，使用暂定站姿作为首帧、已批准走路入口作为尾帧，最短 4 秒，未自动重试。
- Added: 整链接触表、透明外圈 alpha 检查和早期接入相位搜索，用于区分可裁剪区间与不可挽救母片。
- Changed: `stand-right-loop` 按用户意见标记为暂定通过，必须在相邻图边中继续验证，不能单独升级为正式母版。
- Fixed: 无。起步边的尾巴裁切属于原始生成缺陷，未通过后处理掩盖。
- Removed: 无。
- Deprecated: 无。
- Review: `stand-right-to-walk-right` 第 1 次尝试已拒绝。下一次只缩小端点主体并增加左右安全边界，尚未授权提交。

## v0.0.1 · 2026-08-09

- Added: 五百首个 `walk-right-loop` 受控生成任务，使用 Seedance 2.0 完整版、同首尾帧、5 秒、24 fps。
- Added: 从生成母片直接选择连续 27 帧形成 1.125 秒循环候选，并生成 PNG 透明序列、透明 WebP、GIF、MP4 与深浅背景接触表。
- Added: 任务 ID、模型、用量、seed、输入与输出哈希、轮询状态和失败前置校验均写入私有工作区账本，不记录密钥和远端临时 URL。
- Added: 创建公开 GitHub 仓库 `iyuenan3/petsgraph`，使用 MIT License；首个提交只包含公开文档和忽略规则，不包含凭据、宠物照片、生成视频或私有任务账本。
- Changed: AIREADME 同步状态从 `pre-code` 更新为 `phase-0-materials`，运行时代码仍未开始。
- Fixed: 首版色键的青色边缘溢色，改用青幕通道差 alpha 与前景颜色反解；外圈 alpha 已归零。
- Removed: 无。
- Deprecated: 无。
- Review: 用户已通过该候选，状态更新为 `approved-master`；右向整链验收前仍不进入正式素材包。

## v0.0.0 · 2026-08-09

- Added: petsgraph 初始 AIREADME 真相源，共 12 个标准文件。
- Added: 单宠 macOS 第一阶段产品边界、最小互动范围和素材质量优先原则。
- Added: 动作图、逐帧素材、锚点、碰撞、累计 root motion、验收与完整性包契约草案。
- Added: 素材生成 Skill、宠物包编译器、离线运行时和原生窗口运动驱动的目标架构。
- Added: PM red-team、pre-mortem 风险、三次受控尝试止损门和 Phase 0 右向移动闭环。
- Changed: 无，项目仍处于 pre-code。
- Fixed: 无。
- Removed: 无。
- Deprecated: 无。

## Unreleased migration slice · 2026-08-23

- Changed: 原 `codex-pets/` 一次性迁入 `codexpets/packages/public/`，公开清单迁入 `codexpets/manifests/public.json`，管理工具迁入 `codexpets/tools/manage.py`，不保留旧路径兼容入口。
- Added: 公开清单为每只宠物记录 `public=true`、素材所有者和 `ASSETS.md` 授权指针；根忽略规则隔离 Codex 私有包、私有清单和制作工作区。
- Added: 新增标准库回归测试，覆盖公开包清单校验和隔离目录首次安装、重复安装幂等行为。
- Review: 五百与飞流的两个稳定 ID、四个包文件字节数和 SHA-256 均未改变。公开校验器通过，2 项回归测试通过。该切片只完成 Codex 目录迁移，不表示 Player、Studio、PetPack 或宠物事实源已经迁移。

## Unreleased Player path migration · 2026-08-23

- Changed: 根 `Package.swift`、`Sources/`、`Tests/`、`windows/` 与 `global.json` 一次性迁入 `player/macos/` 和 `player/windows/`，平台测试、旧 App 构建入口及日常 Windows CI 同步更新，不保留旧路径兼容入口。
- Changed: 两个 v0.6.0 历史 Release 复验工作流保持发布时的源码差异门禁，目录迁移不修改其安全语义；新 1.0.0 Player 后续建立独立发布链。
- Review: Swift 迁移前后均为 67 项测试通过。Windows 在重新生成锁定依赖资产后为 7 项测试通过，完整解决方案构建 0 警告、0 错误。`player/` 没有真实宠物图片、视频或图集。

## Unreleased brand path migration · 2026-08-23

- Changed: 公开 Logo、ICNS、ICO、PNG 和跨平台图标生成器迁入 `assets/brand/`，Player 与日常 Windows CI 同步使用新路径，不保留 `assets/app-icon/` 兼容入口。
- Changed: 7 个未定稿品牌候选、提示记录和 QA 文件迁入根 Git 忽略的 `studio/brand/`，没有删除，也没有进入公开品牌目录。
- Review: 私有品牌候选迁移前后共 7 个文件、5,378,099 bytes，纯内容摘要保持 `01b055d119af9b37e504cc31264db2e793a589227bd504595a1d59de6865e3e8`。四个公开定稿文件 SHA-256 不变，Windows 解决方案构建 0 警告、0 错误。

## Unreleased Studio path migration · 2026-08-23

- Changed: Seedance、Seedream、GPT Image、生成、抠图、几何、评审、打包和清理工具从公开根 `tools/` 分类迁入根 Git 完整忽略的 `studio/`，不创建独立 Git，也不保留旧路径兼容入口。
- Changed: 根 `.env.example` 与 `.env.local` 机械迁入 `studio/`，真实配置在迁移中从未被读取。工具只读取 Studio 本地配置，不再回退到根目录或 `petsdesk` 的配置路径。
- Changed: 三个可复用的绿幕原型从根 `tmp/` 迁入 `studio/matting/prototypes/`，根 `tools/` 与 `tmp/` 已移除。Studio 仍通过受控项目根定位访问尚未迁移的宠物工作区。
- Review: 共检查 34 个 Python 与 Swift 文件，Python 编译检查和三个 provider 命令入口检查通过。公开 Git 中不存在 Studio 工作副本，`studio/` 没有嵌套 `.git`，全部私有内容保持未跟踪状态。

## Unreleased private responsibility migration · 2026-08-23

- Changed: 五百、飞流、小葵、乔治、红豆、花轮与吉吉资料按职责迁入 `pets/`，旧运行时包迁入 `petpacks/`，五百与飞流的 Codex 私有重建记录迁入 `codexpets/workspaces/`。两批跨宠基础姿态评审归入 `pets/shared/`，不复制到每只宠物。
- Changed: v0.6.0 的 macOS DMG 与 Windows x64 ZIP 本地副本迁入 `.local/dist/published/v0.6.0/`。根 `workspaces/` 与 `dist/` 已退出并从 `.gitignore` 删除，Windows 构建器默认把新候选写入 `.local/dist/builds/`。
- Changed: 现行 Studio 脚本已切换到新路径；历史生产 JSON、提示词和评审记录保留当时写入的旧路径，由 `pets/audit/migrations/` 解析新旧位置，不篡改生产证据。
- Review: 五百 30,496 个文件、7,709,788,770 bytes 与飞流 45,931 个文件、12,977,884,119 bytes 完成完整内容摘要；六个目标组的 inode 集合、文件数与字节数回读一致。小葵 369 个文件只迁移位置，没有生成、抠图或制作 PetPack。
- Review: 五百与飞流 `0.5.10` 完整性文件 SHA-256 分别保持 `59aad356993f6b9cc1f338095bc417cb47090b58e06d46035bb3d7820053529e` 与 `8c4762914b4bfd95b8dc7c9c58d47714f10ac61289774a2f446e7857f4e51516`。GitHub Release 回读确认双平台附件文件名、字节数和 SHA-256 与公开清单一致。

## Unreleased local environment migration · 2026-08-23

- Changed: 通用制作、精细抠图和 Seedance 三个 Python 环境迁入 `.local/environments/`，环境内活动 shebang 与路径记录同步更新；精确安装版本快照保存在私有 `studio/environments/`。
- Changed: 178,648,008-byte 的 rembg `isnet-general-use.onnx` 模型迁入 `.local/cache/rembg/`，SHA-256 保持 `60920e99c45464f2ba57bee2ad08c919a52bbf852739e96947fbb4358c0d964a`。300 个私有可执行脚本切换到新职责路径，历史 JSON、提示词和评审记录不改写。
- Removed: 旧根 Swift `.build/` 缓存共 2,991 个文件、304,741,588 bytes，已移入 `/Users/maxwell/.Trash/PetsGraph-refactor-20260823-022143/root-swift-build-cache` 等待用户复查，inode 集合摘要保持 `5a67252d8c0b5b9e3ab9bff8fe7abb46dd83c16d25e5e470bbfd6ce2a42f0305`。
- Review: 三套环境的核心依赖导入、五个通用制作入口、两个 Seedance 入口、全量私有 Python 语法和 Shell 语法检查通过。rembg 的程序化导入通过；原环境未安装可选 CLI extras，该项不作为迁移回归。

## Unreleased PetPack 1.0 contract · 2026-08-23

- Added: 公开 `petpack/` 提供 manifest、graph、behavior、clip 与 integrity 五份 JSON Schema，标准库参考验证器与 CLI，以及不含真实宠物身份的确定性合成包构建器。
- Added: PetPack `formatVersion=1.0.0` 冻结普通 ZIP、单一 `cropped-rgba-clips` 基线、固定底部中心舞台、被动自主行为、完整有向图、required capabilities 与首版无签名语义。
- Added: 独立公开 CI 在 macOS 与 Windows 运行契约、安全回归、合成包验证和逐字节确定性重建，不读取私有 Studio 或真实宠物包。
- Fixed: 验证器在读取包内容前限制条目、归档、展开大小、单文件、JSON 和压缩比，拒绝前置或尾随载荷、路径越界、跨平台名称冲突、加密、符号链接、可执行内容、重复 JSON key、完整性缺口、媒体长度不符和不可达动作图。
- Security: 成功报告只输出包文件名，不输出完整本机路径或 `pet.displayName`；失败报告使用稳定错误码，不回显包内容、客户路径或生产记录。
- Review: 24 项回归、Python 编译、CLI 验证、store 与 deflate、确定性重建和 Git 差异检查通过。提交夹具共 12 个文件、11,806 bytes，SHA-256 为 `812f0459fe444ff4cf657908d3c9b235be21f591d796ac7d0f02e50f564ac2c1`。本切片不表示五百、飞流正式包或新 Player 已完成。

## Unreleased two-pet PetPack conversion · 2026-08-23

- Added: 私有 Studio 新增旧 schema `0.4.0` 到 PetPack `formatVersion=1.0.0` 的确定性流式转换器，先验证旧包完整性和最终运行时批准，再逐字节复用选中 RGBA 媒体并写入 ZIP64 候选。
- Changed: 五百候选保留 10 个自主 dwell、2 个 gateway 和 26 条非交互边，共 36 个 clip；飞流候选保留 9 个自主 dwell 和 16 条非交互边，共 25 个 clip。旧 interaction 节点、关联边、交互循环、网关停留循环和窗口 root motion 不进入新契约。
- Added: 每个候选旁保存私有 conversion record，记录旧 integrity、最终 review、逐 clip 配方、排除清单、窗口 root motion 处置、输出摘要和公开验证结果，不把私有路径或生产正文写入包内。
- Review: 五百候选为 1,068,381,496 bytes、SHA-256 `14f719b67da95a4cf089500aedc7c67fb6c74c3a63a273052190856f99b3e0ef`；飞流候选为 596,024,359 bytes、SHA-256 `f0308cd322fbbd1ef1259e64ca3f93a8f7da58b202aa441baef5a26fe61aef25`。公开验证器、旧新媒体摘要映射和重复确定性构建均通过，旧包 integrity 摘要未改变。
- Review: 两包仍为 `mechanically-validated-awaiting-player-runtime-review`，只位于私有 `candidates/`。在新 Player 的 Apple Silicon macOS 与 Windows x64 真实桌面验收前，不进入 `approved/`、`delivery/` 或公开发布物。

## Unreleased macOS PetPack 1.0 Player · 2026-08-23

- Changed: Apple Silicon macOS 主线从历史 schema `0.4.0` 内嵌双宠运行时切换到 PetPack `formatVersion=1.0.0` 零素材 Player，不保留旧路径或旧包直接加载兼容层；历史实现继续由 `v0.6.0` 标签和 Release 保存。
- Added: Swift 原生实现普通 ZIP 与 ZIP64、store 与 deflate、安全路径、严格 JSON、完整性、RGBA 媒体长度、canonical 库、幂等导入、升级确认、降级拒绝、cache 重建和卸载。
- Added: 每只宠物使用独立被动行为会话、随机时钟、固定透明舞台、可见状态与位置；菜单只提供装载、显示、隐藏、卸载、全局七档大小和退出，单击不触发动作，视频不推动窗口。
- Added: 新构建器生成 Apple Silicon `0.7.0-dev` ad-hoc 签名 App，强制不包含 `Resources/Pets`、`.petpack` 或真实宠物媒体；独立 macOS CI 运行公开 PetPack 回归、Swift 测试和零素材构建。
- Review: 严格警告编译与 8 项 Swift 测试通过。公开 store 合成包、临时 deflate 合成包、五百与飞流真实候选均由原生加载器验证，零素材 App 架构和签名检查通过。真实 macOS 桌面菜单、拖动、透明命中、多宠长时性能、隐藏恢复、应用升级保留和正常速度视觉验收仍未完成。

## Unreleased Windows PetPack 1.0 Player · 2026-08-23

- Changed: Windows x64 主线从历史 schema `0.4.0` 内嵌双宠运行时切换到 PetPack `formatVersion=1.0.0` 零素材 Player，不保留旧路径或旧包直接加载兼容层；历史实现继续由 `v0.6.0` 标签和 Release 保存。
- Added: C# 原生实现普通 ZIP 与 ZIP64、store 与 deflate、安全路径、严格 JSON、完整性、RGBA 媒体长度、canonical 库、幂等导入、升级确认、降级拒绝、cache 重建和卸载。WPF 渲染显式把包内预乘 RGBA 转换为 `Pbgra32`。
- Added: 每只宠物使用独立被动行为会话、随机时钟、固定透明舞台、可见状态与位置；托盘菜单只提供装载、显示、隐藏、卸载、全局七档大小和退出，单击不触发动作，视频不推动窗口。
- Added: Windows 打包入口生成 `0.7.0-dev` self-contained AMD64 ZIP，强制不包含 `Pets/`、`.petpack` 或真实宠物媒体；Windows CI 定义覆盖锁定还原、测试、WPF 构建、零素材 ZIP、PE 架构和内容边界。
- Security: Windows 安装索引重新验证包 ID、宠物 ID、版本、物种、摘要与归档预算；macOS 同步增加对应校验，损坏或手工改写的索引不能把 canonical 路径导向数据根之外。
- Review: 24 项 Python 回归、18 项 MSTest、9 项 Swift 测试、Windows 全解决方案零警告构建和 Swift 格式检查通过。Windows 原生加载器验证公开 store、临时 deflate、五百和飞流候选，零素材 ZIP 为 PE32+ x86-64 且不含宠物包。真实 Windows 11 GUI、双平台正常速度观看、应用升级、多宠长时性能、远端 CI 和正式发布仍未完成。

## Unreleased PetPack forward compatibility alignment · 2026-08-23

- Fixed: Windows Player 不再拒绝未知可选能力或缺失的节点与场景权重覆盖，缺失权重统一按 `1.0` 处理；macOS 同步验证能力标识格式。未知必需能力仍由三个实现拒绝。
- Added: 新增确定性前向兼容测试包 `synthetic-cat-forward-v1.petpack`，共 12 个文件、11,774 bytes，SHA-256 为 `d0f5273cbf930e2ddd12865a62311d0d2058c4a1749b07b33448d84411ca08dc`。原基线包逐字节重建摘要保持不变。
- Review: 25 项 Python 回归、10 项 Swift 测试、19 项 MSTest、Windows Release 零警告构建、`dotnet format` 与 `swift-format lint` 通过。C# 原生验证器顺序验证基线、前向兼容、deflate、五百和飞流五个包；临时零素材 Windows x64 ZIP 的 SHA-256 为 `8ff625331bcd052f3d16fba111f9c2368603802e13602840e5954d9b267cf55c`。真实双平台 GUI、正常速度视觉与远端 CI 仍待验收。

## Unreleased refactor acceptance audit · 2026-08-23

- Fixed: macOS 与 Windows 的旧运行时迁移不再复用旧显示状态，只在 package ID 明确匹配时迁移位置，并继续迁移全局大小；新增双平台回归防止隐藏状态越过一次性架构切换。
- Added: `docs/audits/refactor-2026-08-23.md` 逐条映射 12 项重构目标、可恢复清理、公开私有边界、包摘要、测试、开发产物、远端门禁和人工验收步骤。
- Review: 25 项 Python、11 项 Swift、20 项 MSTest 与 2 项 Codex 回归通过。Windows 全解决方案 Release 构建 0 警告、0 错误，两个原生加载器验证同一五包集合。新构建的 macOS arm64 App 与 Windows x64 ZIP 均为零宠物素材开发产物。远端 push、CI、真实双平台 GUI 与正常速度视觉批准仍未完成。

## Unreleased cross-platform hostile ZIP fixtures · 2026-08-23

- Fixed: Python 参考验证器在 Windows 上改用 `ZipInfo.orig_filename` 检查归档原始条目名，防止标准库先把反斜线改成正斜线后绕过 `unsafe_path` 分类。
- Fixed: Python 安全测试绕过 `ZipInfo` 写入阶段的主机分隔符规范化，明确断言归档实际包含反斜线；本地测试同时模拟 Windows `os.sep`，避免 macOS 假绿。
- Fixed: C# 恶意 symlink 测试包固定最后一个中央目录条目的 Unix 创建主机标记，使 Unix mode 在 macOS 与 Windows Runner 上具有相同含义，不放宽生产验证器。
- Review: 首次远端 push 的 macOS 工作流通过，PetPack contract 与 Windows x64 工作流分别暴露上述两个问题。修复后 25 项 Python、Python 编译、20 项 MSTest 与 `dotnet format` 本地通过；远端再次运行仍待回读。

## Unreleased remote refactor CI verification · 2026-08-23

- Fixed: 将 `1937a03`、`f6b855f` 与文档锚点推送到远端，未使用强制推送；远端 `main` 独立回读为 `97485a0c5ccc557748773738dac5e009cf221753`。
- Review: PetPack contract 运行 `32596460282` 在 macOS 14 与 Windows 2025 上全部通过；macOS Apple Silicon 运行 `32596460260` 完成测试、零素材 App 构建和上传；Windows x64 运行 `32596460309` 完成锁定还原、20 项测试、WPF 构建、self-contained ZIP、AMD64 PE、零素材和上传。
- Review: 远端 macOS 与 Windows 代码开发产物分别为 1,806,750 和 77,508,772 bytes，保留 7 天。这些 CI 产物不是正式 Release，真实双平台 GUI、同包正常速度观看和用户批准仍未完成。

## Unreleased final refactor hardening · 2026-08-23

- Fixed: PetPack 三个实现对齐严格 ZIP、单一媒体表示、32 位整数边界、SemVer 构建元数据与完整版本路径身份。参考验证器新增显式目录、条目注释、强加密、条目间隙和数据描述符拒绝，共 33 项 Python 回归。
- Fixed: macOS 与 Windows Player 新增持久导入激活日志、首装与更新失败回滚、进程中断恢复、事务卸载、保守设置恢复、真实媒体摘要校验、完整过渡预加载和长时间帧索引保护。Swift 21 项、MSTest 38 项通过，Windows Release 构建 0 警告、0 错误。
- Fixed: CodexPets 多宠安装改为全有或全无，并先验证 SHA-256、显示名与目标集合，3 项回归通过。历史 Release 复验改为从不可移动标签读取源码和清单，只读验证已经公开的冻结附件。
- Changed: macOS 人工安装候选优先构建到 `/private/tmp`，避免 Desktop File Provider 在签名后异步加入 Finder 元数据。最终审查构建 3 严格签名和零素材检查通过，但安装启动被 Mac 锁屏阻断。
- Review: 构建 2 的公开合成宠物在真实桌面观察到动画刷新。该证据不覆盖五百、飞流身份、完整菜单、拖动、正常速度观看或 Windows 11 x64 GUI，整个重构 Goal 保持未完成。
- Review: PetPack、macOS、Windows 最终审查运行 `32600312955`、`32600330583`、`32600330777` 全部成功。历史 `v0.6.0` 的 macOS 与 Windows 公开附件只读复验 `32600568305`、`32600570363` 也全部成功。

## Unreleased macOS review build 3 installation · 2026-08-23

- Changed: 将严格签名和零素材检查通过的 `/private/tmp/PetsGraph-0.7.0-review3.app` 可恢复安装到 `/Applications/PetsGraph.app`，原构建 2 移入系统回收站保留。宠物库、cache、位置和设置均未删除。
- Review: 安装后二进制版本为 `0.7.0-review`、构建号 3，主程序 SHA-256 为 `ce6717898384ff42c9ba40175ebb7640aa83ce2b1d8946cd67e59659985a7520`。严格签名、arm64、仅图标资源和基线、前向兼容、五百、飞流四包原生校验通过。Mac 仍锁屏，GUI 启动和真实宠物观看继续保持未通过。

## Unreleased macOS review build 4 memory and desktop verification · 2026-08-23

- Fixed: macOS 启动和包校验的流式 `FileHandle.read` 循环增加逐块 `autoreleasepool`，避免 AppKit 事件循环开始前的 Foundation 临时缓冲累计到完整媒体体积。对同一五百候选执行原生校验，最大常驻内存由 build 3 的 2,162,049,024 bytes 降至 build 4 的 19,333,120 bytes。
- Added: macOS 与 Windows 各增加一项确定性独立随机时钟回归。Swift 22 项、MSTest 39 项、格式检查和远端运行 `32626076785`、`32626076781` 全部通过。
- Changed: `/private/tmp/PetsGraph-0.7.0-review4.app` 已可恢复安装到 `/Applications/PetsGraph.app`，build 3 移入系统回收站。安装后二进制版本 `0.7.0-review`、构建号 4、arm64、1,209,088 bytes，SHA-256 为 `db70b62c0c6e4ba1d277126d6b54cb88541342d54582b6effbc06b90f293b326`，严格签名、零素材和四包原生校验通过。
- Fixed: GUI 自动化遗留的 `Synthetic Cat` 合成夹具是桌面彩色色块闪烁的来源，不是空播放器背景。测试资料库已完整移入系统回收站，真正空库启动没有宠物窗口；随后只装载五百与飞流候选。
- Review: build 4 双宠 GUI 运行 21 秒后的物理占用为 55.8 MB，稳定取样约 3.3% CPU，只有一个进程且没有当天崩溃报告。两只默认睡眠循环各 4 个正常速度样本都随呼吸变化，隐藏状态与统一倍率可跨重启恢复。状态栏菜单、透明命中拖动、卸载、完整动作链长时间观看和用户视觉批准仍是人工门禁；Windows x64 真实 GUI 按用户当前指示暂缓。
