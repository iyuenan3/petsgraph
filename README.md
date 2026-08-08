# petsgraph

petsgraph 是一个面向真实宠物的开源 macOS 桌面宠物项目。它优先解决宠物身份一致性、动作自然度、陪伴感，以及动作与原生桌面窗口位移的同步。

项目目前处于 Phase 0 素材验证阶段，运行时代码尚未开始。当前正在用单只真实宠物验证第一条右向移动闭环：

`站立 → 走路 → 跑步 → 走路 → 站立`

## 核心原则

- 第一阶段只支持单宠物和 macOS。
- 动作采用直接生成视频、逐帧验收和动作图编排。
- 走路与跑步素材在画面内原地运动，由运行时 root motion 驱动原生窗口横向移动。
- 左右方向使用独立生成素材，不默认镜像真实宠物。
- PNG 序列帧是素材制作真相源，图集是后续编译产物，动态 WebP 只用于预览或导出。
- 机械检查只做辅助，身份一致性、动作自然度与衔接质量由人工视觉验收决定。
- 用户自行配置 Seedance 等生成服务，本项目不提供付费素材生成或私密照片托管服务。

## 当前仓库内容

- [`AIREADME/CORE.md`](AIREADME/CORE.md)：产品身份、范围与质量红线
- [`AIREADME/PRD.md`](AIREADME/PRD.md)：第一阶段产品需求与验收标准
- [`AIREADME/SPEC.md`](AIREADME/SPEC.md)：宠物素材包与动作图数据契约草案
- [`AIREADME/ARCHITECTURE.md`](AIREADME/ARCHITECTURE.md)：生成、编译、播放器和窗口运动架构
- [`AIREADME/ROADMAP.md`](AIREADME/ROADMAP.md)：Phase 0 到素材生成 Skill 的路线
- [`AIREADME/DECISIONS.md`](AIREADME/DECISIONS.md)：关键产品与技术决策

真实宠物照片、生成任务记录和未批准素材属于本地私有工作区，不包含在公开仓库中。

## 状态

当前已经完成并人工批准第一只宠物的右向慢走循环母版。站立节点、跑步、过渡动作、素材包编译器和桌面运行时仍待实现。

在首条移动闭环通过真实桌面验收之前，本项目不会批量生成完整动作集。

## License

[MIT](LICENSE)
