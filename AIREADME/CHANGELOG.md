# CHANGELOG：petsgraph

> Append-only。记录版本与里程碑，决策理由见 `DECISIONS.md`。

## v0.0.1 · 2026-08-09

- Added: 五百首个 `walk-right-loop` 受控生成任务，使用 Seedance 2.0 完整版、同首尾帧、5 秒、24 fps。
- Added: 从生成母片直接选择连续 27 帧形成 1.125 秒循环候选，并生成 PNG 透明序列、透明 WebP、GIF、MP4 与深浅背景接触表。
- Added: 任务 ID、模型、用量、seed、输入与输出哈希、轮询状态和失败前置校验均写入私有工作区账本，不记录密钥和远端临时 URL。
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
