# SPEC：petsgraph 宠物素材包 v0.2

> 本契约是素材生成 Skill 与桌面运行时之间的边界。schema `0.2.0` 已由 Swift 加载器、行为规划器、包编译器和正式五百本地包实现。`0.1.0` 工程包继续作为只读历史证据。

## 1. 契约范围

- 安装单元：一个只包含一只宠物的本地 `.petsgraph-pet` 目录或压缩包。
- 制作事实源：RGBA PNG 序列、动作清单、图结构、验收记录和完整性清单。
- 运行时产物：第一版直接使用 PNG 序列；后续可以从同一事实源编译分页图集。
- 预览产物：动态 WebP、GIF 或 MP4，不是运行时事实源。
- 隐私边界：安装包不携带原始宠物照片、生成凭据、提示词私密上下文或可执行脚本。

## 2. 目录布局

```text
<package-id>.petsgraph-pet/
  package.json
  graph.json
  behavior.json
  clips/
    <clip-id>.json
  frames/
    <clip-id>/
      0000.png
      0001.png
  atlases/                 # 可选，可重建的运行时编译物
    atlas-000.png
    atlas-000.json
  previews/                # 可选，不参与运行时寻址
    <clip-id>.webp
  reviews/
    index.json
    <subject-id>.json
  integrity.json
```

素材制作工作区可以另存视频母片、原始照片、提示词和分割中间件，但这些内容不得默认进入安装包。

## 3. `package.json`

```json
{
  "schemaVersion": "0.2.0",
  "package": {
    "id": "example-pet-v1",
    "version": "1.0.0",
    "createdAt": "2026-08-09T00:00:00+08:00"
  },
  "pet": {
    "id": "example-pet",
    "displayName": "Example Pet",
    "species": "cat",
    "identityStyle": "identity-faithful-lightly-stylized"
  },
  "art": {
    "canvasPx": [480, 480],
    "baseHeightPt": 120,
    "coordinateOrigin": "top-left",
    "defaultNode": "rest.prone.left"
  },
  "renderAssets": {
    "mode": "frames",
    "pixelFormat": "rgba8-straight"
  },
  "graph": "graph.json",
  "behavior": "behavior.json",
  "reviewIndex": "reviews/index.json",
  "integrity": "integrity.json"
}
```

约束：

- `package.id`、`pet.id` 和版本号不可通过覆盖旧文件改变既有已批准包；新素材使用新版本。
- `baseHeightPt` 是 root motion 和桌面显示的参考高度，不锁死用户最终显示大小。
- 第一阶段只接受一个宠物、一个默认睡眠节点、一个动作图和一个行为配置。
- `renderAssets.mode` 首版必须是 `frames`；`atlas` 在真实原型证明收益后再启用。

## 4. 坐标与缩放

- 图像坐标使用像素，原点在画布左上角，x 向右，y 向下。
- 所有矩形数组统一写成 `[x, y, width, height]`；椭圆数组表示其外接矩形。
- 锚点、内容包围盒与碰撞区域使用图像像素坐标。
- `rootMotionPt` 使用 `baseHeightPt` 下的桌面逻辑点，记录从片段起点开始的累计位移。
- 运行时缩放因子：`scale = displayHeightPt / baseHeightPt`。
- 运行时窗口位置：`windowX(t) = actionStartX + scale × rootMotionPt.x(t)`。
- 自动动作的 `rootMotionPt.y` 必须始终为 `0`。用户拖动产生的窗口 y 偏移不写入 clip root motion。
- 累计位移是事实源。不得只存相邻帧 delta，避免掉帧、暂停和恢复后累积漂移。
- 一个宠物包只有一套画布和地面坐标。不同母片的地面不一致时，编译器只能对每条已批准动作路径的副本应用一个固定变换，再把锚点写入全包坐标；不得修改批准源帧或逐帧重新定位。
- 普通睡姿、枕头睡姿、坐姿及其内部过渡的所有逐帧与终点 root motion 必须严格为 `[0,0]`。只有批准的枕头场景进出边可以在 MVP 中产生水平累计位移。已保留的走路、跑步及相关过渡继续使用同时间轴累计位移，但不进入默认睡眠行为。

## 5. `graph.json`

节点描述动作端点的兼容姿态、视觉场景和产品职责。稳定姿态使用 `stability=stable`，走路和跑步循环使用 `stability=cyclic`。

```json
{
  "schemaVersion": "0.2.0",
  "nodes": [
    {
      "id": "rest.prone.left",
      "displayName": "趴卧",
      "posture": "prone",
      "orientation": "left",
      "grounded": true,
      "stability": "stable",
      "scene": "floor",
      "role": "dwell",
      "autonomousEligible": true,
      "props": [],
      "loopClip": "prone-left-loop-v1"
    },
    {
      "id": "gateway.pillow.b",
      "displayName": "靠枕过渡",
      "posture": "leaning-rest",
      "orientation": "right",
      "grounded": true,
      "stability": "stable",
      "scene": "pillow",
      "role": "gateway",
      "autonomousEligible": false,
      "props": ["pillow"],
      "loopClip": "pillow-gateway-leaning-right-loop-v1"
    }
  ],
  "edges": [
    {
      "id": "prone-left-to-pillow-gateway-right",
      "from": "rest.prone.left",
      "to": "gateway.pillow.b",
      "clip": "prone-left-to-pillow-rest-right-v2",
      "kind": "transition",
      "interruptPolicy": "finish-before-retarget",
      "sceneChange": "floor-to-pillow"
    }
  ]
}
```

节点约束：

- 节点不能只写模糊的 `stand` 或 `sit`，必须包含 `posture + orientation`；需要时再增加支撑关系或视角标签。
- 每个正式节点可以提供面向用户的 `displayName`。安静陪伴包的所有自主 `dwell` 节点必须提供非空中文显示名，否则加载器拒绝安装。
- 正式菜单、状态栏和普通反馈只使用 `displayName` 或受控中文回退文案，不能泄露节点 ID、clip ID 或边 ID。
- `orientation` 第一阶段支持 `front`、`left`、`right`。
- `scene` 首个 MVP 支持 `floor` 与 `pillow`。场景改变必须由显式边完成。
- `role` 支持 `dwell`、`gateway`、`interaction` 和 `cyclic`。`gateway` 与 `interaction` 必须设置 `autonomousEligible=false`。
- 普通正面坐姿使用 `sit.front.floor`。枕头场景使用独立 `sit.front.pillow`，不能把没有枕头的坐姿当成同一节点。现有历史包中的 `sit.front` 作为 `sit.front.floor` 的兼容 ID，迁移必须通过带版本号新包完成。
- `props` 声明节点画面必须持续包含的道具。目标节点与入口 clip 的道具集合不兼容时拒绝切换。
- 循环节点必须有 `loopClip`，稳定节点的循环必须能够无限停留。

边约束：

- `kind` 支持 `transition`、`finite-activity`、`locomotion-transition`。
- 边是有向的。反向动作必须有独立边和独立验收，不能默认倒放。
- `finite-activity` 可以从一个稳定节点回到同一节点，用于玩耍、进食和舔毛等完整有限动作。
- 普通边只能从来源片段的安全退出帧进入；强中断按 `interruptPolicy` 处理。
- 运行时必须验证默认节点可以到达所有必需能力，并存在返回某个稳定节点的路径。
- 睡眠 MVP 必须验证每个自主 `dwell` 节点都能到达当前场景的 `interaction` 坐姿并返回睡眠。网关不计入自主睡姿覆盖率。
- 运行时动作集合由节点的 `loopClip` 和边的 `clip` 引用推导，并按 `clips/<clip-id>.json` 显式寻址。不得依赖目录枚举结果决定动作图是否完整。
- 必需片段、帧、图、行为配置、演示序列和评审索引都必须出现在 `integrity.json`。必需文件缺失、哈希变化、符号链接或带 hidden 文件标记时，运行时拒绝加载。

### 5.1 `behavior.json`

行为配置描述宠物如何使用动作图，不复制 clip 或边定义。睡眠 MVP 至少包含：

```json
{
  "schemaVersion": "0.2.0",
  "profile": "quiet-sleep-companion",
  "defaultIntent": "sleep",
  "timing": {
    "strategy": "random-long-tail",
    "parametersStatus": "runtime-review-pending",
    "avoidImmediateRepeat": true
  },
  "scenePolicy": {
    "pillow": {
      "sticky": true,
      "gateway": "gateway.pillow.b"
    }
  },
  "interactions": {
    "petClick": {
      "sleeping": "wake-to-scene-sit",
      "sitting": "return-to-scene-sleep"
    },
    "desktopClick": "ignore",
    "drag": "direct-manipulation"
  }
}
```

约束：

- `random-long-tail` 的具体时间参数必须经过真实时间行为验收后才能从 `runtime-review-pending` 升级。
- 行为层只能选择 `autonomousEligible=true` 的节点。
- `desktopClick=ignore` 表示运行时不得为了行为功能安装全桌面点击监听。
- 点击目标按当前 `scene` 解析，不能从 `pillow` 硬切到 `floor` 坐姿。
- 拖动清除尚未开始的普通目标，保留用户放置的 x 与 y；松手后从兼容稳定姿态恢复。
- 菜单指定睡姿只接受 `autonomousEligible=true` 的 `dwell` 节点。睡眠状态立即规划到目标，坐姿先返回当前场景睡眠后再规划目标。
- 已经播放的有限过渡不能被菜单选择截断。过渡期间的新选择覆盖尚未开始的旧选择，只保留最后一个有效目标。

## 6. `clips/<clip-id>.json`

```json
{
  "schemaVersion": "0.2.0",
  "id": "walk-right-loop-v1",
  "type": "loop",
  "facing": "right",
  "mirrorSafe": false,
  "entryPose": "gait.walk.right",
  "exitPose": "gait.walk.right",
  "safeExitFrames": [0, 8, 16, 24],
  "preloadHints": ["run-right-accelerate-v1", "walk-right-stop-v1"],
  "rootMotionEndPt": [48.0, 0.0],
  "provenance": {
    "approvalStatus": "human-action-approved",
    "approvedRecipe": "workspaces/example-private/actions/walk-right-loop/v1/approved-recipe.json",
    "approvedRecipeSha256": "<lowercase-sha256>",
    "rootMotionStatus": "runtime-chain-approved",
    "normalization": "pet-global-fixed-transform-v1"
  },
  "frames": [
    {
      "src": "frames/walk-right-loop-v1/0000.png",
      "durationMs": 42,
      "contentBoundsPx": [82, 96, 318, 286],
      "petBoundsPx": [96, 110, 224, 250],
      "propBoundsPx": {},
      "anchorsPx": {
        "root": [240, 350],
        "ground": [240, 382],
        "head": [302, 166]
      },
      "collision": {
        "bodyCoreEllipsePx": [145, 185, 198, 132],
        "screenBoundsPx": [82, 96, 318, 286],
        "petHitEllipsePx": [145, 185, 198, 132]
      },
      "rootMotionPt": [0.0, 0.0]
    }
  ]
}
```

片段约束：

- `type` 支持 `loop`、`transition`、`finite`。
- 每帧有独立 `durationMs`，不假设整个包只有一个 FPS。
- `contentBoundsPx` 是该帧实际可见 alpha 包围盒，用于屏幕边缘预测和固定窗口内布局。
- `petBoundsPx` 只覆盖宠物可见主体。`propBoundsPx` 按道具 ID 记录道具区域。没有道具时写空对象。
- `anchorsPx.root` 是视觉与 root motion 统一参考点；`ground` 是主要地面接触基线；`head` 用于交互和未来视线目标。
- `bodyCoreEllipsePx` 是宠物核心区域；`petHitEllipsePx` 或未来逐帧宠物命中掩码用于点击宠物本体。
- `screenBoundsPx` 表示该帧不能越过可用显示区域的猫与道具联合可见区域。枕头不能扩大 `petHitEllipsePx`。
- `rootMotionPt` 必须从同一视频时间轴提取并记录累计值。向左片段 x 应非正推进，向右片段 x 应非负推进。
- `rootMotionEndPt` 是片段终点的累计样本。最后一帧仍有正时长时，运行时在最后一帧的 `rootMotionPt` 与该终点样本之间插值，避免片段边界发生位置跳变。
- 从稳定姿态进入步态的过渡可以先保持零位移，但必须在第一步明确朝目标方向迈出时开始累计 root motion，并在进入目标循环前连续收敛到已批准的循环速度。右向累计 x 不得回退，左向累计 x 不得前进；素材画面通过不等于该位移曲线通过。
- `safeExitFrames` 由足部接触、稳定姿态和人工检查共同确定。有限过渡默认不可被普通自主行为中断。
- 预加载提示只是优化建议，不能改变图语义。
- 新编译的批准片段必须在 `provenance.approvedRecipeSha256` 固定私有批准配方的精确内容。编译器复制帧前必须验证配方哈希、主体 ID、批准状态、事实源路径、批准帧数、FPS 和有序序列摘要。该字段只允许历史兼容包缺省，缺省包不得因此自动升级批准状态。
- `demo-sequence.json` 只是显式评审链，不是绕过动作图的播放清单。`transition` 片段必须从第 0 帧完整播放一次；相邻片段的 `exitPose` 与 `entryPose` 必须一致；循环之后还有下一片段时，循环最后播放的运行时帧必须在 `safeExitFrames` 中。
- 运行时必须在当前循环安全退出前解析并预加载下一条边或目标循环。预加载失败不得以硬切、截断过渡或跳到目标第 0 帧降级。

## 7. 李五百睡觉陪伴 MVP 必备能力

合规 MVP 包必须提供：

- 默认睡眠节点及至少三种可长期停留的普通睡姿。
- 每个自主节点都有批准循环、安全退出帧和返回路径。
- 普通场景正面坐姿 `sit.front.floor`，以及从所有首发普通睡姿到该坐姿再返回睡眠的有界路径。
- 枕头场景网关、至少两种枕头睡姿、`sit.front.pillow` 和完整双向路径。
- 枕头只通过显式场景边出现和离开，同一枕头场景中的节点保持道具集合一致。
- 点击、全桌面拖动、隐藏、退出和恢复行为。
- 以中文名称列出全部自主睡姿，并允许用户指定其中任意一个目标。
- 睡眠内部严格零 root motion。枕头进出边如含短步，必须使用批准的水平累计 root motion。

### MVP 最小图基线

五百 `0.3.0` 使用 schema `0.2.0` 的已实现节点基线：

| 节点 | scene | role | 作用 |
|---|---|---|---|
| `rest.prone.left` | floor | dwell | 默认趴卧睡姿和普通场景汇合点 |
| `rest.side-curled.left` | floor | dwell | 左侧蜷卧 |
| `rest.side-stretched.left` | floor | dwell | 左侧伸展 |
| `rest.supine.left` | floor | dwell | 仰卧 |
| `rest.curled-supine.left` | floor | dwell | 蜷缩仰卧 |
| `rest.semi-supine.left` | floor | dwell | 松散半仰卧 |
| `rest.sleeping-loaf.left` | floor | dwell | 睡眠香箱 |
| `gateway.loaf.legacy.left` | floor | gateway | 旧香箱兼容汇合点，不参与随机停留 |
| `sit.front.floor` | floor | interaction | 普通睡眠点击后的正面坐姿 |
| `gateway.pillow.b` | pillow | gateway | 枕头场景进入、离开、预加载和唤醒汇合 |
| `rest.pillow.head-on` | pillow | dwell | 头趴枕头睡姿 |
| `rest.pillow.compact-semi-supine` | pillow | dwell | 枕头支撑的紧凑半仰卧 |
| `rest.pillow.top-curled` | pillow | dwell | 整个身体蜷睡在枕头上 |
| `sit.front.pillow` | pillow | interaction | 保留枕头的正面坐姿 |

最低路径要求：

- 普通 `dwell` 节点构成至少一个不硬切的闭合睡眠子图。
- 每个首发普通 `dwell` 节点能在点击响应目标内到达 `sit.front.floor`，并能返回普通睡眠。
- `rest.prone.left → gateway.pillow.b` 和独立回程连接两个场景。反向不能倒放正向素材。
- 网关与每个首发枕头睡姿有批准路径；枕头内部至少存在一条不经过网关的随机换姿路径。
- 每个首发枕头睡姿能经批准醒来路径到达 `sit.front.pillow`，并能返回枕头睡眠。
- 网关与两个坐姿均设置 `autonomousEligible=false`。

已经批准的站立、走路、跑步和左右过渡可以继续存在于同一素材事实库或工程包，但睡眠 MVP 的 `behavior.json` 不得请求它们。`↔` 仍表示两个分别生成、分别验收的有向边，不表示倒放。

## 8. 生成母片与运行时片段

- 一个生成任务可以产出一条较长的连续母片，再确定性切出多个运行时片段。
- 例如一条 `趴卧→侧躺→稳定呼吸→返回趴卧` 母片可以切出出站边、稳定循环和独立回程边。
- 切分只允许选择连续直接帧、统一画布、重定位、抠图和编码，不允许交叉淡化、光流、RIFE 或自动补间。
- 每个切出的运行时片段仍需独立机械检查；涉及图边时还要验收首尾接缝和完整链。

## 9. 验收契约

`reviews/index.json` 记录每个动作、图边和整链的状态，不依赖文档口头描述。

状态层级：

1. `draft`
2. `mechanical-pass`
3. `human-action-approved`
4. `human-edge-approved`
5. `runtime-chain-approved`
6. `rejected`

每条验收记录至少包含：

- `subjectType` 与 `subjectId`
- 被验收文件的 SHA-256
- 检查时的显示高度、浅色背景、深色背景和真实桌面背景
- 机械检查摘要及其非最终性声明
- 人工验收人、时间、明确结论和备注
- 是否允许进入安装包

必需路径没有达到 `runtime-chain-approved` 时，包验证器必须拒绝正式安装。预览模式可以加载 draft，但必须显著标记为未批准。

睡眠 MVP 的整包评审还必须记录：

- 真实时间行为观察的时长、睡眠占比、姿势切换次数、场景切换次数和是否出现近期重复。
- 点击到首个可见醒来反应、到完整坐姿、再次点击到恢复睡眠的时间。
- 普通场景和枕头场景的道具连续性、点击命中与拖动结果。
- 默认启动没有安装全桌面点击 monitor，也不要求辅助功能权限。
- 用户放置的 y 在随机睡姿、点击和枕头场景内部切换中保持不变。

### 9.1 已批准素材的生产履历

每个进入 `human-action-approved` 或 `human-edge-approved` 的动作或图边，都必须在私有制作工作区保存独立的 `approved-recipe.json`。每只宠物还必须维护 `approved-assets.json`，逐项索引当前已批准版本及其履历路径。生产履历是跨猫狗复用生成方法的依据，不是运行时安装包内容。

`approved-recipe.json` 至少记录：

- 宠物、动作或图边 ID、版本、批准状态、批准时间、人工结论、评审证据和剩余验收闸门。
- provider、模型、任务 ID、受控尝试序号、实际自动重试次数，以及是否产生过未计费的前置校验失败。
- 提示词文件路径和 SHA-256。每个输入记录角色、路径、SHA-256 与来源说明。
- 时长、分辨率、比例、音频、水印等生成参数，以及原始母片路径、SHA-256、seed、FPS 和总帧数。
- 被采用的连续原始帧起止、排除帧、片段时长、下一动作入口相位和循环旋转顺序。
- 抠图、画布处理和编译脚本的路径、版本或 SHA-256，以及是否禁用了补间、光流、RIFE、骨骼和交叉淡化。
- 按文件名排序的 PNG 制作事实源总帧数、总字节数和序列摘要，以及关键输出文件的 SHA-256。
- 图入口姿态、出口姿态、安全退出策略、已批准的相邻入口相位、已知取舍与可复用于其他宠物的方法。
- 当前是否可安装。未达到 `runtime-chain-approved` 时必须明确列出剩余闸门。

PNG 序列摘要固定按文件名字典序处理。每帧依次写入 UTF-8 文件名、一个 NUL 字节、小写文件 SHA-256 十六进制文本和一个 LF 字节，最后对完整字节流计算 SHA-256。实现不得依赖文件系统遍历顺序。

可复现性分为两层：已有母片到运行时事实源的确定性处理必须能够按脚本和哈希复现；生成 provider 即使记录相同 seed，也不保证再次生成逐像素相同结果，因此履历保证方法、输入和选择可追溯，不承诺随机模型逐像素重演。

生产履历禁止保存密钥、访问令牌、签名 URL、临时下载地址和未脱敏日志。原始私密照片可以只留在受控工作区，履历只记录本地角色、相对路径、哈希和来源说明。若历史素材缺少某项信息，必须显式记录为不可恢复的已知限制，不能用推测值补齐；新素材不得带着此类缺口进入批准状态。

## 10. 完整性与安全

- `integrity.json` 对所有运行时文件保存 SHA-256、字节数和媒体类型。
- 导入时拒绝绝对路径、`..` 越界、符号链接逃逸、未知 schema 主版本和哈希不匹配。
- 宠物包不得包含可执行文件、动态库、脚本入口、provider token 或任意运行时网络地址。
- 坏包不得导致运行时崩溃；验证失败时不替换当前可用宠物包。
- 逐帧抠图失败不得静默复用上一帧蒙版。失败帧必须标记、修复并重新验收，或拒绝该片段。
- `behavior.json` 只能引用图中存在的场景、网关和交互目标。无法满足点击往返或把非自主节点加入候选集时拒绝安装。
- 枕头节点缺少宠物命中区域、道具区域或联合屏幕边界时，只能进入显式工程预览，不能成为正式 MVP 包。

## 11. 版本与兼容

- `schemaVersion` 使用语义化版本。
- `0.1.0` 包是走跑与睡眠工程预览契约。`0.2.0` 已加入必需的 `behavior.json`、节点职责、场景和猫道具命中字段，并由加载器、编译器和回归测试执行。
- 公开宠物包版本 `0.3.0` 继续使用 schema `0.2.0`，只新增向后兼容的节点 `displayName` 数据和运行时指定睡姿交互，不改变帧、坐标或动作图语义。
- App 名称、Bundle ID 与宠物包身份是不同契约。运行时使用 `PetsGraph` 与 `com.maxwell.petsgraph`；当前宠物名称来自 `package.json.pet.displayName`，不能写死在通用菜单或反馈中。
- `0.3.1` 继续使用 schema `0.2.0`，帧与 `0.3.0` 完全一致。版本变化只涉及 App 品牌分层、动态宠物名称和发布载体。
- 同一主版本新增未知字段时，旧运行时应忽略未知字段并读取已知部分。
- 未知主版本必须拒绝，并给出可读错误。
- 任何改变坐标、root motion、图语义或验收要求的变更都视为潜在破坏性变更，必须追加 ADR 并升级 schema。
