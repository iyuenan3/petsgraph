# SPEC：petsgraph 宠物素材包 v0（draft）

> 本契约是素材生成 Skill 与桌面运行时之间的边界。它将在首条真实动作链完成后根据证据定稿。

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
  "schemaVersion": "0.1.0",
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
    "defaultNode": "stand.front"
  },
  "renderAssets": {
    "mode": "frames",
    "pixelFormat": "rgba8-premultiplied"
  },
  "graph": "graph.json",
  "reviewIndex": "reviews/index.json",
  "integrity": "integrity.json"
}
```

约束：

- `package.id`、`pet.id` 和版本号不可通过覆盖旧文件改变既有已批准包；新素材使用新版本。
- `baseHeightPt` 是 root motion 和桌面显示的参考高度，不锁死用户最终显示大小。
- 第一阶段只接受一个宠物、一个默认节点和一个动作图。
- `renderAssets.mode` 首版必须是 `frames`；`atlas` 在真实原型证明收益后再启用。

## 4. 坐标与缩放

- 图像坐标使用像素，原点在画布左上角，x 向右，y 向下。
- 所有矩形数组统一写成 `[x, y, width, height]`；椭圆数组表示其外接矩形。
- 锚点、内容包围盒与碰撞区域使用图像像素坐标。
- `rootMotionPt` 使用 `baseHeightPt` 下的桌面逻辑点，记录从片段起点开始的累计位移。
- 运行时缩放因子：`scale = displayHeightPt / baseHeightPt`。
- 运行时窗口位置：`windowX(t) = actionStartX + scale × rootMotionPt.x(t)`。
- 第一阶段 `rootMotionPt.y` 必须始终为 `0`，宠物只在水平活动带移动。
- 累计位移是事实源。不得只存相邻帧 delta，避免掉帧、暂停和恢复后累积漂移。
- 一个宠物包只有一套画布和地面坐标。不同母片的地面不一致时，编译器只能对每条已批准动作路径的副本应用一个固定变换，再把锚点写入全包坐标；不得修改批准源帧或逐帧重新定位。
- 趴卧、侧躺及其互转等原地休息链的所有逐帧与终点 root motion 必须严格为 `[0,0]`。走路、跑步及相关过渡继续使用同时间轴累计位移驱动原生窗口。

## 5. `graph.json`

节点描述动作端点的兼容姿态。稳定姿态使用 `stability=stable`，走路和跑步循环使用 `stability=cyclic`。

```json
{
  "schemaVersion": "0.1.0",
  "nodes": [
    {
      "id": "stand.right",
      "posture": "stand",
      "orientation": "right",
      "grounded": true,
      "stability": "stable",
      "loopClip": "stand-right-idle-v1"
    },
    {
      "id": "gait.walk.right",
      "posture": "walk",
      "orientation": "right",
      "grounded": true,
      "stability": "cyclic",
      "loopClip": "walk-right-loop-v1"
    }
  ],
  "edges": [
    {
      "id": "stand-right-to-walk-right",
      "from": "stand.right",
      "to": "gait.walk.right",
      "clip": "walk-right-start-v1",
      "kind": "transition",
      "interruptPolicy": "direct-manipulation-only"
    }
  ]
}
```

节点约束：

- 节点不能只写模糊的 `stand` 或 `sit`，必须包含 `posture + orientation`；需要时再增加支撑关系或视角标签。
- `orientation` 第一阶段支持 `front`、`left`、`right`。
- `sit.front` 表示面向用户的方向中立坐姿，不拆成左右两个坐姿节点。它可以分别连接左向和右向移动边，转身、起身和迈步由对应有向边表达。
- 循环节点必须有 `loopClip`，稳定节点的循环必须能够无限停留。

边约束：

- `kind` 支持 `transition`、`finite-activity`、`locomotion-transition`。
- 边是有向的。反向动作必须有独立边和独立验收，不能默认倒放。
- `finite-activity` 可以从一个稳定节点回到同一节点，用于玩耍、进食和舔毛等完整有限动作。
- 普通边只能从来源片段的安全退出帧进入；强中断按 `interruptPolicy` 处理。
- 运行时必须验证默认节点可以到达所有必需能力，并存在返回某个稳定节点的路径。
- 运行时动作集合由节点的 `loopClip` 和边的 `clip` 引用推导，并按 `clips/<clip-id>.json` 显式寻址。不得依赖目录枚举结果决定动作图是否完整。
- 必需片段、帧、图、演示序列和评审索引都必须出现在 `integrity.json`。必需文件缺失、哈希变化、符号链接或带 hidden 文件标记时，运行时拒绝加载。

## 6. `clips/<clip-id>.json`

```json
{
  "schemaVersion": "0.1.0",
  "id": "walk-right-loop-v1",
  "type": "loop",
  "facing": "right",
  "mirrorSafe": false,
  "entryPose": "gait.walk.right",
  "exitPose": "gait.walk.right",
  "safeExitFrames": [0, 8, 16, 24],
  "preloadHints": ["run-right-accelerate-v1", "walk-right-stop-v1"],
  "rootMotionEndPt": [48.0, 0.0],
  "frames": [
    {
      "src": "frames/walk-right-loop-v1/0000.png",
      "durationMs": 42,
      "contentBoundsPx": [82, 96, 318, 286],
      "anchorsPx": {
        "root": [240, 350],
        "ground": [240, 382],
        "head": [302, 166]
      },
      "collision": {
        "bodyCoreEllipsePx": [145, 185, 198, 132],
        "screenBoundsPx": [82, 96, 318, 286]
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
- `anchorsPx.root` 是视觉与 root motion 统一参考点；`ground` 是主要地面接触基线；`head` 用于交互和未来视线目标。
- `bodyCoreEllipsePx` 是粗碰撞区域；第一阶段不做宠物间碰撞，但仍用于屏幕约束和交互扩展。
- `screenBoundsPx` 表示该帧不能越过可用显示区域的可见区域。
- `rootMotionPt` 必须从同一视频时间轴提取并记录累计值。向左片段 x 应非正推进，向右片段 x 应非负推进。
- `rootMotionEndPt` 是片段终点的累计样本。最后一帧仍有正时长时，运行时在最后一帧的 `rootMotionPt` 与该终点样本之间插值，避免片段边界发生位置跳变。
- 从稳定姿态进入步态的过渡可以先保持零位移，但必须在第一步明确朝目标方向迈出时开始累计 root motion，并在进入目标循环前连续收敛到已批准的循环速度。右向累计 x 不得回退，左向累计 x 不得前进；素材画面通过不等于该位移曲线通过。
- `safeExitFrames` 由足部接触、稳定姿态和人工检查共同确定。有限过渡默认不可被普通自主行为中断。
- 预加载提示只是优化建议，不能改变图语义。

## 7. 第一阶段必备能力

合规包必须提供：

- 站立、坐下、趴卧和至少一种侧躺，共至少两种躺姿。
- 每个稳定姿态至少一个可停留循环。
- 左右独立的走路和跑步链，包含起步、循环、走跑切换、减速和停步。
- 玩耍、进食和舔毛，允许先作为从稳定姿态返回同一姿态的有限活动。
- 所有跨姿态变化的有向过渡，至少覆盖默认节点到上述能力再返回默认稳定节点的路径。
- 正式左右动作 `mirrorSafe=false`，不得用运行时镜像补齐缺失方向。

### 第一阶段最小图基线

必需节点：

| 节点 | 类型 | 作用 |
|---|---|---|
| `stand.front` | stable | 默认姿态、玩耍与进食的回归枢纽 |
| `stand.left` / `stand.right` | stable | 左右位移动作的起点和终点 |
| `sit.front` | stable | 坐姿、舔毛和躺卧入口 |
| `lie.belly.front` | stable | 趴卧循环与侧躺入口 |
| `lie.side.left` / `lie.side.right` | stable | 两侧侧躺，保留真实左右特征 |
| `gait.walk.left` / `gait.walk.right` | cyclic | 左右慢走循环 |
| `gait.run.left` / `gait.run.right` | cyclic | 左右快跑循环 |

必需有向边：

- `stand.front ↔ stand.left`、`stand.front ↔ stand.right`：转向与侧身。
- `stand.left ↔ gait.walk.left`、`stand.right ↔ gait.walk.right`：起步与停步。
- `gait.walk.left ↔ gait.run.left`、`gait.walk.right ↔ gait.run.right`：独立加速与减速。
- `stand.front ↔ sit.front`：站立与坐下。
- `sit.front ↔ lie.belly.front`：坐下、趴卧与起身。
- `lie.belly.front ↔ lie.side.left`、`lie.belly.front ↔ lie.side.right`：趴卧与左右侧躺。
- `stand.front → stand.front`：玩耍和进食有限活动，各自独立片段。
- `sit.front → sit.front`：舔毛有限活动。

`↔` 表示必须存在两个分别生成、分别验收的有向边，不表示倒放或自动复用。

## 8. 生成母片与运行时片段

- 一个生成任务可以产出一条较长的连续母片，再确定性切出多个运行时片段。
- 例如一条 `站立→起步→多个走路周期→停步→站立` 母片可以产出 `walk_start`、`walk_loop` 和 `walk_stop`。
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

## 11. 版本与兼容

- `schemaVersion` 使用语义化版本。
- 同一主版本新增未知字段时，旧运行时应忽略未知字段并读取已知部分。
- 未知主版本必须拒绝，并给出可读错误。
- 任何改变坐标、root motion、图语义或验收要求的变更都视为潜在破坏性变更，必须追加 ADR 并升级 schema。
