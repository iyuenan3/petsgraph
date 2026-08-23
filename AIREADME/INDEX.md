# PetsGraph · AIREADME
> 面向宠物离世纪念的开源多宠 Player 与私有定制 PetPack 体系 ｜ 生命周期: implementation-in-progress
> last-synced: 80d5763 · 2026-08-23
> phase: refactor-complete-macos-accepted / windows-gui-deferred

当前公开 `v0.6.0` 仍是内嵌五百与飞流的旧架构发布版。PetPack 1.0 公开 schema、参考验证器、合成包与安全回归已经实现，五百与飞流已经形成私有候选。Apple Silicon macOS 与 Windows x64 `0.7.0-dev` 均已实现零素材 Player、持久导入激活日志、失败与重启回滚、事务卸载、保守状态恢复、独立行为时钟、固定舞台与目标菜单。Swift 32 项、MSTest 44 项和相关远端运行通过，回归覆盖双宠状态、四边贴靠、透明命中坐标、七档精确标签、隐藏过渡、cache 删除与损坏重建、更新失败回滚、卸载中断恢复、共享最快帧率调度和转场最近帧缓存；Python、Swift 与 C# 对五百和飞流同一候选包的摘要与图结构结果一致。用户已经确认 build 16 的卸载重装、显示隐藏、目标状态灰显、Dock 区域拖出、四边贴靠、七档大小、重启保持、透明穿透、点击无动作和正常速度视觉表现全部通过。macOS build 17 进一步把多宠调度和鼠标监听合并为进程级资源，并在稳定隐藏后释放渲染对象；单宠连续画面、0.50% 平均 CPU、49.4 MB 物理占用和隐藏飞流零媒体映射已经机械回读，双宠共享监听、全隐藏深度休眠、真实鼠标拖动和完整自主转场继续后续观察。Windows 真实 GUI 验收按当前要求暂缓，五百与飞流仍保持私有候选，正式交付和 `1.0.0` 发布属于后续里程碑。后续报告仍必须显式区分 Target、机械实现、人工验收、候选包与已发布 As-built。

## 状态

| 文件 | 状态 | 摘要 |
|---|:---:|---|
| CORE | ✅ | 纪念陪伴定位、零素材 Player、客户自持 PetPack、私有 Studio 与硬约束 |
| RELATIONS | ✅ | Player、Studio、PetPack 三层边界及 provider、GitHub 与历史运行时关系 |
| SPEC | ✅ | PetPack 1.0 行为、ZIP 容器、单一 RGBA 基线、完整性、安全、首版无签名、状态菜单灰显与 macOS Dock 层级契约已实现；双平台原生装载已实现 |
| ARCHITECTURE | ✅ | 目标组件、固定舞台、多宠独立时钟、macOS 共享调度与隐藏资源释放、包激活事务、双平台新实现和历史边界 |
| DIRECTORY | ✅ | 唯一项目根、公开与私有子树、已迁移源码、Studio、宠物事实源、旧包与本地产物边界 |
| DEPLOYMENT | ✅ | macOS build 5 至 17 实机与机械证据、Windows 44 项测试和精确倍率标签、同包机械一致性及 v0.6.0 历史基线 |
| PRD | ✅ | 离世客群、定制服务、多宠独立时钟、菜单、隐藏卸载和成功指标 |
| ROADMAP | ✅ | 目录、PetPack、双宠候选、双平台 Player 与同包机械一致性已完成，继续 build 17 双宠、全隐藏和真实拖动观察 |
| CONVENTIONS | ✅ | 公开私有边界、客户目录、生成配置、慢动作、抠图与包生命周期约定 |
| DECISIONS | ✅ | 追加 ADR-044 至 ADR-055，记录纪念定位、三层架构、PetPack 基线、包激活事务、系统临时构建、共享调度和执行护栏 |
| MEMORY | ✅ | 追加纯色背景色族、原生慢动作、完整链优先、工具链匹配、旧进程识别、帧提交热点、菜单灰显、Dock 层级与回收站恢复边界经验 |
| CHANGELOG | ✅ | 记录 2026-08-23 目录迁移、PetPack 1.0、双宠候选、双平台 Player、build 10 至 17、共享调度、隐藏资源释放和完整复验证据 |

## 按任务读

- 跨项目了解产品与边界 → `CORE.md` + `RELATIONS.md`
- 设计或实现 PetPack → `SPEC.md` + `ARCHITECTURE.md` + `CONVENTIONS.md` + `DECISIONS.md`
- 规划、迁移或清理目录 → `DIRECTORY.md` + `ARCHITECTURE.md` + `CONVENTIONS.md` + `DECISIONS.md`
- 修改多宠、菜单、显示隐藏、卸载、固定位置或大小 → `PRD.md` + `SPEC.md` + `ARCHITECTURE.md`
- 生成小葵或其他客户素材 → `PRD.md` 第 6 至 7 节 + `CONVENTIONS.md` + `MEMORY.md`
- 划分公开 Player 与私有 Studio → `CORE.md` + `RELATIONS.md` + `ARCHITECTURE.md` + `CONVENTIONS.md`
- 盘点或迁移 v0.6.0 旧实现 → `ARCHITECTURE.md` 第 12 至 13 节 + `DEPLOYMENT.md` + `CHANGELOG.md`
- 构建、安装、发布或回滚当前版本 → `DEPLOYMENT.md` + `CHANGELOG.md`
- 核对本轮重构逐项证据与人工门禁 → `../docs/audits/refactor-2026-08-23.md`
- 讨论下一阶段优先级 → `PRD.md` + `ROADMAP.md`
- 复盘实际失败 → `MEMORY.md`，重大取舍另向 `DECISIONS.md` 追加
- 维护 Codex 宠物导出 → `DIRECTORY.md` 第 10 节 + `SPEC.md` 第 14 节 + `DEPLOYMENT.md` 的 Codex 章节

同步锚点指向 macOS 共享调度与隐藏资源释放代码、测试和 build 17 审计提交 `80d5763`。它继承 `9c76976` 的下一代重构完成状态、`fdc2024` 的 build 16 最终人工验收，以及更早的 PetPack 1.0、双平台原生 Player、同包一致性、透明命中、Dock 层级、四边贴靠、倍率标签和事务恢复证据。当前复验通过 32 项 Swift 测试、严格格式、零素材 arm64 构建、构建后与安装后严格签名、唯一进程启动和单宠连续画面资源回读。build 16 的真实菜单、透明穿透、点击无动作、拖动和正常速度视觉结论继续有效；build 17 没有改动拖动回调或媒体速度，但双宠共享监听、全隐藏深度休眠、真实鼠标拖动和完整自主转场仍需后续实际观察。Windows 真实 GUI 验收暂缓，五百与飞流保持私有候选，正式交付和 `1.0.0` 发布仍属于后续里程碑。
