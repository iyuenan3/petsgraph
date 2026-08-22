# PetsGraph · AIREADME
> 面向宠物离世纪念的开源多宠 Player 与私有定制 PetPack 体系 ｜ 生命周期: implementation-in-progress
> last-synced: dff512e · 2026-08-23
> phase: directory-migration-complete / petpack-implementation-next

当前公开 `v0.6.0` 仍是内嵌五百与飞流的旧架构发布版。下一代零素材 Player 与外部 `.petpack` 已完成产品决策但尚未实现；公开源码、私有 Studio、宠物事实源、旧包、Codex 工作区与本地发布归档均已切入职责目录，后续实现仍必须显式区分 Target 与 As-built。

## 状态

| 文件 | 状态 | 摘要 |
|---|:---:|---|
| CORE | ✅ | 纪念陪伴定位、零素材 Player、客户自持 PetPack、私有 Studio 与硬约束 |
| RELATIONS | ✅ | Player、Studio、PetPack 三层边界及 provider、GitHub 与历史运行时关系 |
| SPEC | ✅ | PetPack 1.0 行为、ZIP 容器、RGBA 基线、装载、兼容、完整性和安全契约已定，尚待实现 |
| ARCHITECTURE | ✅ | 目标组件、固定舞台、多宠状态、内部宠物库、当前 v0.6.0 与迁移边界 |
| DIRECTORY | ✅ | 唯一项目根、公开与私有子树、已迁移源码、Studio、宠物事实源、旧包与本地产物边界 |
| DEPLOYMENT | ✅ | 下一代零素材分发目标与 v0.6.0 双平台历史发布基线 |
| PRD | ✅ | 离世客群、定制服务、多宠独立时钟、菜单、隐藏卸载和成功指标 |
| ROADMAP | ✅ | 职责目录与本机环境收口已完成，继续实现 PetPack 1.0 并重构双平台运行时 |
| CONVENTIONS | ✅ | 公开私有边界、客户目录、生成配置、慢动作、抠图与包生命周期约定 |
| DECISIONS | ✅ | 追加 ADR-044 至 ADR-051，记录纪念定位、三层架构、目录、PetPack 基线和执行护栏 |
| MEMORY | ✅ | 追加纯色背景色族、原生慢动作和完整链优先的制作经验 |
| CHANGELOG | ✅ | 记录 2026-08-23 重构契约与首个目录迁移切片，新运行时仍未实现 |

## 按任务读

- 跨项目了解产品与边界 → `CORE.md` + `RELATIONS.md`
- 设计或实现 PetPack → `SPEC.md` + `ARCHITECTURE.md` + `CONVENTIONS.md` + `DECISIONS.md`
- 规划、迁移或清理目录 → `DIRECTORY.md` + `ARCHITECTURE.md` + `CONVENTIONS.md` + `DECISIONS.md`
- 修改多宠、菜单、显示隐藏、卸载、固定位置或大小 → `PRD.md` + `SPEC.md` + `ARCHITECTURE.md`
- 生成小葵或其他客户素材 → `PRD.md` 第 6 至 7 节 + `CONVENTIONS.md` + `MEMORY.md`
- 划分公开 Player 与私有 Studio → `CORE.md` + `RELATIONS.md` + `ARCHITECTURE.md` + `CONVENTIONS.md`
- 盘点或迁移 v0.6.0 旧实现 → `ARCHITECTURE.md` 第 12 至 13 节 + `DEPLOYMENT.md` + `CHANGELOG.md`
- 构建、安装、发布或回滚当前版本 → `DEPLOYMENT.md` + `CHANGELOG.md`
- 讨论下一阶段优先级 → `PRD.md` + `ROADMAP.md`
- 复盘实际失败 → `MEMORY.md`，重大取舍另向 `DECISIONS.md` 追加
- 维护 Codex 宠物导出 → `DIRECTORY.md` 第 10 节 + `SPEC.md` 第 14 节 + `DEPLOYMENT.md` 的 Codex 章节

同步锚点指向已审阅并提交的本机环境与缓存收口切片 `dff512e`。AIREADME 自身随后单独提交，目录迁移已完成，但新 Player 与 PetPack 1.0 仍未实现。
