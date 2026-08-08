# CHANGELOG：petsgraph

> Append-only。记录版本与里程碑，决策理由见 `DECISIONS.md`。

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
