# SPEC：PetsGraph Player 与 PetPack

> Target: PetPack 1.0 的产品语义、ZIP 容器和 `cropped-rgba-clips` 长期兼容媒体基线已经确定。As-built: 公开 schema、标准库参考验证器、合成包与安全回归已经实现，五百与飞流已经形成私有机械验证候选，macOS 与 Windows Player 已接入原生装载、canonical 库与行为会话；当前公开 `v0.6.0` 仍加载 schema `0.4.0` 的 `.petsgraph-pet` 并内嵌两只宠物。各层不得混写成同一已实现状态。

## 1. 契约范围

PetPack 是私有制作系统与公开 PetsGraph Player 之间唯一的运行时数据边界：

- 一个 `.petpack` 只包含一只猫或狗。
- 包是不可变、可离线保存的客户交付物。
- Player 可以同时装载多个包，但不把多只宠物合成一个共享动作图。
- 包只描述宠物身份、媒体、固定舞台、动作图、独立时钟和完整性，不携带平台窗口、用户位置、全局倍率、脚本或 provider 信息。
- 同一包必须能被 Apple Silicon macOS 与 Windows x64 Player 消费。未来 Player 也必须能够实现同一公开契约。

## 2. 术语

| 术语 | 含义 |
|---|---|
| source file | 用户收到并自行长期保存的原始 `.petpack` |
| canonical copy | Player 装载后复制到内部宠物库的不可变正式副本 |
| cache | 可删除并从 canonical copy 重建的解包、索引、解码或缩略图数据 |
| package ID | 同一只已交付宠物包谱系的稳定标识 |
| content version | 该宠物媒体、图或行为配置的版本 |
| format version | PetPack 结构和语义版本 |
| node | 可长期停留的稳定视频状态或明确的短时网关状态 |
| edge | 从一个节点到另一个节点的独立生成有向过渡 |
| fixed stage | 宠物在单一透明参考画布内活动，Player 窗口不随视频动作移动 |

## 3. 目标目录布局

`.petpack` 对用户表现为单个文件。目标逻辑布局如下：

```text
<package-id>.petpack
  manifest.json
  graph.json
  behavior.json
  media/
    <clip-id>/
      <representation-id>.<ext>
  clips/
    <clip-id>.json
  integrity.json
```

容器冻结为普通 ZIP，文件扩展名为 `.petpack`。归档必须从 ZIP 本地文件头开始，各本地记录连续排列，并在 ZIP 结束记录处结束，不能包含前置、条目间隙、数据描述符或尾随载荷。归档根直接包含上述清单，不增加一层同名目录，也不写入显式目录条目、归档注释或条目注释。条目名使用 UTF-8、NFC Unicode 与 `/` 分隔符；禁止传统加密、强加密、分卷、绝对路径、`..`、反斜线、控制字符、符号链接、可执行权限、可执行内容、重复规范路径、Windows 保留名和大小写折叠后冲突。条目压缩只允许 store 或 deflate，允许 ZIP64，以容纳大型长期媒体。参考验证器的默认上限为 100,000 个条目、64 GiB 包文件、64 GiB 总展开大小、32 GiB 单条目、16 MiB 单 JSON 和 200 倍压缩比。Player 必须先验证中央目录、路径和展开后大小预算，再把内容复制到内部 canonical 库或解包到可重建 cache。

首个 PetPack `formatVersion=1.0.0` 的必需透明媒体基线冻结为 `cropped-rgba-clips`：每个 clip 恰好包含一个整段固定裁剪框、sRGB、预乘 `RGBA8` 连续原始帧流，正式倍率为 `1.0x`。后续格式版本可以增加可选 representation，但任何未来 Player 都不能因此放弃对 1.0 基础表示的兼容性。

公开测试向量同时包含基线包 `synthetic-cat-v1.petpack` 与前向兼容包 `synthetic-cat-forward-v1.petpack`。后者声明 Player 未知的可选能力 `future-audio`，并省略节点与场景权重覆盖，用于证明未知可选能力不会阻止装载，缺失权重按 `1.0` 处理。Python 参考验证器、Swift 原生加载器与 C# 原生加载器必须对这两个语义保持一致；未知必需能力仍必须拒绝。

禁止把客户原始照片、视频母片、提示词、任务记录、评审视频、生成凭据或私有制作目录装入正式包。

## 4. `manifest.json`

目标字段示例：

```json
{
  "formatVersion": "1.0.0",
  "package": {
    "id": "example-pet",
    "contentVersion": "1.0.0",
    "createdAt": "2026-08-22T00:00:00+08:00"
  },
  "pet": {
    "id": "example-pet",
    "displayName": "示例宠物",
    "species": "cat"
  },
  "stage": {
    "referenceCanvasPx": [960, 960],
    "anchor": "bottom-center",
    "baseDisplayHeight": 180,
    "defaultNode": "rest.primary"
  },
  "capabilities": {
    "required": ["cropped-rgba-clips"],
    "optional": []
  },
  "graph": "graph.json",
  "behavior": "behavior.json",
  "integrity": "integrity.json"
}
```

约束：

- `package.id` 在同一宠物谱系中稳定，不能因为换平台而改变；首个 1.0 要求 `pet.id` 与它相同。
- `contentVersion` 只在媒体、动作图、行为或包级显示事实改变时提升。
- `pet.displayName` 用于菜单，Player 不写死具体宠物名称。
- `species` 第一版允许 `cat` 与 `dog`，但动作语义和验收不因物种字段自动套模板。
- `referenceCanvasPx`、`anchor` 和 `baseDisplayHeight` 定义固定舞台与该宠物自己的基础体型。
- 用户全局倍率不写入包。最终显示大小为 `baseDisplayHeight × globalScale`。
- 包内不保存用户桌面位置、显示或隐藏状态、最近动作、Player 平台和安装路径。

## 5. 动作图

`graph.json` 描述节点和有向边，不是随机视频列表：

```json
{
  "formatVersion": "1.0.0",
  "nodes": [
    {
      "id": "rest.primary",
      "role": "dwell",
      "scene": "floor",
      "loopClip": "rest-primary-loop",
      "autonomousEligible": true
    }
  ],
  "edges": [
    {
      "id": "rest-primary-to-rest-secondary",
      "from": "rest.primary",
      "to": "rest.secondary",
      "clip": "rest-primary-to-rest-secondary",
      "interruptPolicy": "finish-before-retarget"
    }
  ]
}
```

节点约束：

- `dwell` 是可以长期停留的稳定状态，必须有可连续播放的循环。
- `gateway` 只承担离场、入场、遮挡或场景汇合，不进入普通自主候选。
- PetPack 1.0 没有 `interaction` 角色。历史坐姿如果自然进入生活链，可以迁移为自主 `dwell` 或过渡端点，但不能绑定用户点击。
- `scene` 表示宠物与紧密道具形成的视觉上下文。宠物与猫窝、饭碗等接触道具可以作为同一媒体单元，不要求 Player 进行物理合成。
- 稳定节点、短时网关和过渡都使用固定参考画布与底部中心锚点。

边约束：

- 每条边有明确来源与目标，只能按原帧顺序完整播放。
- 反向动作是另一条独立生成、独立验收的边，不能倒放正向素材。
- 不允许用镜像、交叉淡化、RIFE、光流、自动补间、帧复制或硬切构造边。
- 普通循环只能在包声明的安全退出点进入下一条边。
- 下一条边和目标循环必须在退出前预加载；失败时留在当前稳定循环，不得跳到目标。
- 两个状态之间没有批准边时，Player 必须视为不可达，不能自行切换。

## 6. `behavior.json`

行为配置属于每只宠物，不由 Player 写死：

```json
{
  "formatVersion": "1.0.0",
  "profile": "passive-memorial-companion",
  "defaultNode": "rest.primary",
  "timing": {
    "strategy": "independent-random-dwell",
    "dwellRangesSeconds": {
      "rest.primary": [30, 60]
    },
    "avoidImmediateRepeat": true
  },
  "nodeWeights": {},
  "sceneWeights": {}
}
```

约束：

- Player 为每个已装载包创建独立时钟、随机状态、当前节点和停留截止时间。
- 多只宠物可以同时过渡，不共享随机目标，不因另一只宠物的显示、隐藏、拖动或卸载改变状态。
- 调度只能选择 `autonomousEligible=true` 的节点，并由图规划器沿合法边到达。
- 正式运行不是按 QA 完整链固定轮播，也不能从 clip 数组中随机硬切。
- 用户不能通过点击或菜单改变动作目标。
- Player 重启后从包的默认稳定节点开始，不模拟离线期间经过的动作。
- 隐藏时画面立即消失。当前过渡在后台完成到稳定节点后暂停行为时钟和解码；再次显示从稳定状态继续。

## 7. `clips/<clip-id>.json` 与媒体

每个 clip 至少声明：

- `id`、`type`、原生帧率或逐帧时长、帧数和持续时间。
- 固定参考画布、固定底部中心锚点和整段固定几何。
- 循环的安全退出点，过渡的入口与出口节点。
- 首个 1.0 恰好一个 `cropped-rgba-clips` 媒体 `representation`，包含编码、分辨率、Alpha、色彩空间、帧率、字节数和 SHA-256。
- 原生连续帧状态、正式播放倍率和任何速度处理记录。
- 对应批准配方与评审记录的私有摘要指针，不包含客户路径或提示词正文。

媒体约束：

- 正式倍率固定为 `1.0x`。呼吸和其他慢动作必须在生成阶段达到最终节奏。
- 同一 clip 内不能逐帧重新缩放、重定位或跟随 Alpha 包围盒裁切。
- 固定裁剪只改变存储窗口，不能改变统一画布中的主体位置和锚点。
- Alpha 与边缘处理必须在整段使用一致的背景色族模型，不能逐帧调参造成毛发闪烁。
- 首个 1.0 不进行 representation 选择。未来格式允许增加可选表示时，Player 也不得通过降帧、改速或跳过过渡静默降级。
- PetPack 1.0 必须包含 `cropped-rgba-clips` 基础表示。它声明固定 crop、宽高、`bytesPerRow = width × 4`、帧数、帧率或逐帧时长、预期总字节数和 SHA-256；媒体长度必须与这些字段严格一致。
- `presentationOffsetPx` 必须等于固定 crop 的左上角坐标，Player 据此把裁剪帧恢复到统一参考画布中的原位置。
- 小葵以后可以验证更小的透明视频或图像 representation，但它只能作为附加能力，不能替换或废弃已经交付包的基础表示。

## 8. Player 多宠宿主契约

- 一个 Player 进程可以装载多个不重复 `package.id` 的包。
- 每只宠物拥有独立窗口或舞台实例、位置、可见状态、行为会话和媒体缓存。
- 全局倍率范围是 `0.5` 至 `2.0`，一次作用于所有已装载宠物，并跨启动保存。
- 拖动只改变该宠物固定锚点，不写入包，也不触发动作。
- 窗口不读取或执行 clip root motion。新目标包的桌面位置在整个视频图中保持固定。
- macOS 宠物窗口必须位于 Dock 前方，同时低于系统主菜单、状态栏和弹出菜单；不能用普通浮动窗口层级让 Dock 遮挡宠物，也不能用过高层级盖住系统关键界面。
- Player 不协调多只宠物的动作时间，不提供宠物互动、碰撞或自动避让。
- 新装载宠物默认放在不重叠位置，用户拖动后允许重叠。

菜单契约：

```text
装载宠物包…

显示宠物
  全部
  <已装载宠物动态列表>

隐藏宠物
  全部
  <已装载宠物动态列表>

卸载宠物
  全部
  <已装载宠物动态列表>

大小
  0.5 至 2.0

关于 PetsGraph

退出 PetsGraph
```

Player 不提供动作、睡姿、场景或声音菜单。

“关于 PetsGraph”读取当前安装 App 的版本号与构建号，显示 App 图标，并说明 Player 与独立 `.petpack` 宠物内容的边界。版本信息不能在菜单代码中写死。

显示与隐藏子菜单必须反映当前状态：已经显示的宠物在“显示宠物”中禁用，已经隐藏的宠物在“隐藏宠物”中禁用；当全部宠物已经处于目标状态时，对应“全部”同样禁用。状态变化后必须在下次展开菜单时立即反映。

## 9. 装载、更新与卸载

macOS As-built 在系统层注册 `.petpack` 文件类型。状态栏文件选择与访达双击必须进入同一装载事务，文件关联只提供入口便利，不能绕过验证、canonical copy、原子提交或失败回滚。其他平台可以采用不同入口，但不能改变下述事务语义。

装载事务：

1. 在临时位置读取并验证完整包。
2. 拒绝绝对路径、`..` 越界、符号链接、未知必需能力、哈希不匹配和可执行内容。
3. 确认本平台存在可播放 media representation。
4. 复制完整 source file 或其规范化不可变副本到内部 canonical 库。
5. 在持久导入激活日志中记录旧版本、新版本和 staged 路径，再原子更新注册表。
6. 创建并启动对应运行时窗口后提交激活；任一步失败或进程在提交前退出，下次启动都回滚注册表、canonical copy 与 cache，继续使用原有宠物。

重复与更新：

- 相同 `package.id`、相同 `contentVersion` 是幂等装载。
- 更高版本需要用户确认后原子替换，保留位置和可见状态；失败继续使用旧版。
- 更低版本默认拒绝，除非未来提供明确降级流程。
- 不同 `package.id` 作为新宠物装载。

卸载：

- 删除内部 canonical copy、缓存和该宠物本地设置。
- 不删除用户外部保存的 source file。
- 卸载全部必须二次确认并明确再次恢复需要原始 `.petpack`。

## 10. 版本与长期兼容

- 当前参考验证器严格接受 `formatVersion=1.0.0`，未知格式版本和未声明字段一律拒绝并给出可读错误。schema 先约束版本形状，三个实现再把 SemVer 核心分量限制在 32 位有符号整数范围内；构建元数据不影响版本优先级，但包文件身份仍使用完整版本字符串，避免把两个不同构建误认为同一路径。
- 未知必需能力必须拒绝，未知可选能力可以忽略。新增结构或 representation 需要显式的新格式版本，不能在 1.0.0 中暗加字段。
- 一旦某包在 Player 中成功装载，其基础动作图、时序、锚点和媒体必须在后续 Player 继续可用。
- Player 升级不得把 canonical copy 放在应用安装目录，也不得在迁移时原位改写正式包。
- 新功能只能通过 Player 兼容能力或新版 `.petpack` 增量提供。旧包缺少声音等新内容时继续静音播放。
- 平台 Player 可以有不同导入 UI、窗口或全屏呈现，但不能改变包内动作图和生命节奏。

## 11. 完整性、安全与隐私

- `integrity.json` 为除自身外的每个运行时文件保存规范相对路径、字节数、媒体类型和 SHA-256，并要求覆盖集合完全相等。
- 包不得包含脚本、动态库、插件入口、绝对路径、符号链接、网络请求、provider token、签名 URL 或客户原始资料。
- 路径使用 `/`、区分稳定大小写规则并做 Unicode 规范化，避免 macOS 与 Windows 解析差异。
- 坏包、重复包、更新失败和解码失败不得让 Player 崩溃或替换当前可用宠物。
- 首个 `formatVersion=1.0.0` 不接受 `signature.json`。其中的哈希用于发现损坏和内部不一致，不证明制作来源，也不阻止能够同时改写内容与清单的人修改包。
- 五百与飞流的首批 PetPack 1.0 只实现 `integrity.json`。官方签名算法、信任根和 UI 语义在装载、更新、卸载和双平台播放稳定后另行冻结，并通过后续显式格式契约加入。
- 未来签名只证明来源与内容身份，不限制复制、备份、离线播放或开源 Player 的实现。
- 参考验证器成功报告不输出本机完整路径或 `pet.displayName`，失败报告不回显包内容、客户路径或私有制作记录。

## 12. 制作与验收契约

正式生产顺序：

```text
客户资料与习惯证据
  → 身份母版
  → 未抠图连续视频与完整动作链
  → 单段、接缝和完整图正常速度人工验收
  → 整体背景色族抠图与去色溢
  → 固定几何
  → PetPack 编译
  → macOS 与 Windows 真实 Player 验收
```

每个批准单元至少记录 provider、模型、任务 ID、输入摘要、提示词摘要、原始母片摘要、原生 FPS、帧数、正式倍率、速度处理、连续原始帧范围、抠图配方、固定几何、输出摘要和人工结论。记录不得包含密钥、临时下载地址或客户外部可识别路径。

批准层级至少区分身份、单动作、图边、完整未抠图链、统一抠图链、双平台运行时和可交付包。机械校验或某一段通过不能自动提升后续状态。

## 13. Legacy as-built：`.petsgraph-pet` schema `0.4.0`

当前 `v0.6.0` 实现仍使用目录型 `.petsgraph-pet`：

```text
<package-id>.petsgraph-pet/
  package.json
  graph.json
  behavior.json
  clips/
  media/
  reviews/
  integrity.json
```

- 渲染模式是 `cropped-rgba-clips`，每个 clip 使用固定裁剪的预乘 RGBA 连续帧流。
- Swift 与 .NET 加载器验证 schema、图、安全路径、固定 crop、媒体长度和完整性。
- 旧包支持点击坐姿、指定睡姿、内嵌包发现、逐帧 root motion 和历史角色 `interaction`。
- v0.6.0 在 macOS DMG 与 Windows ZIP 中内嵌五百、飞流两个 `0.5.10` 包。
- 这些事实继续作为离线转换输入，不是 PetPack 1.0 的目标交互和分发方式。新 Player 不直接装载 schema `0.4.0`。
- 迁移不得修改已经批准的媒体字节、帧序、正式速度和固定几何。旧交互节点可以在新行为图中废弃，或在确实自然时改为自主生活状态，但不能继续暴露点击操作。
- 五百与飞流由私有 Studio 转换器生成新 `.petpack`，只保留自主睡眠、换姿和已批准自主活动；点击坐立、步行、interaction 与窗口 root motion 不进入新包。转换失败继续保留旧批准包和 `v0.6.0` 回滚事实。
- 精确的旧发布事实、摘要和验证结果见 `DEPLOYMENT.md`、`CHANGELOG.md` 与 Git 标签。

## 14. Codex 宠物导出契约

当前 As-built 已使用 `codexpets/`。公开包、公开清单、管理工具和文档在提交 `76ad2ea` 同步切换，原 `codex-pets/` 与 `tools/manage-codex-pets.py` 不保留兼容入口。

目标 `codexpets/` 是独立于 PetsGraph Player 的小型 Codex v2 自定义宠物制作与分发面：

- 每个目录只包含 `pet.json` 与 1536×2288 RGBA `spritesheet.webp`，使用 8 列、11 行、每格 192×208 的 v2 图集。
- 公开包位于 `codexpets/packages/public/<package-id>/`；私有包位于根 Git 忽略的 `codexpets/packages/private/`。
- `codexpets/manifests/public.json` 固定公开目录、ID、显示名、字节数、SHA-256、`public=true`、素材所有者和 `licenseRef`，不得包含私有包条目或客户元数据。
- `codexpets/manifests/private.json` 保持私有，不得向公开清单泄漏客户 ID、宠物名、路径或摘要。
- 当前公开导出为五百 `wubai-v0` 与飞流 `feiliu-hatch-native-v1`；迁移后四个包文件的媒体字节与摘要保持不变。
- Codex 专用选帧、生成、布局和 QA 位于 `codexpets/workspaces/<pet-id>/`，通过相对路径和摘要引用 `pets/` 唯一事实源，不复制客户原始资料。
- Codex 图集的机械通过不映射为 PetPack 连续视频、生命感、动作图或可交付批准。
- Codex 导出不进入 `.petpack`，也不改变 Player 零内置宠物素材的目标。

目录、根 Git 跟踪与迁移门禁见 `DIRECTORY.md` 第 10 至 14 节。
