# PetsGraph · AIREADME
> 面向宠物离世纪念的开源多宠 Player 与私有定制 PetPack 体系 ｜ 生命周期: implementation-in-progress
> last-synced: f6b855f · 2026-08-23
> phase: dual-platform-player-implemented / desktop-acceptance-next

当前公开 `v0.6.0` 仍是内嵌五百与飞流的旧架构发布版。PetPack 1.0 公开 schema、参考验证器、合成包与安全回归已经实现，五百与飞流已经形成私有机械验证候选。Apple Silicon macOS 与 Windows x64 `0.7.0-dev` 均已实现零素材 Player、原生 PetPack 校验、canonical 库、被动行为会话、固定舞台与目标菜单；真实桌面人工验收、双平台视觉与性能一致性、候选批准和可交付正式包尚未完成。后续报告仍必须显式区分 Target、机械实现、人工验收、候选包与已发布 As-built。

## 状态

| 文件 | 状态 | 摘要 |
|---|:---:|---|
| CORE | ✅ | 纪念陪伴定位、零素材 Player、客户自持 PetPack、私有 Studio 与硬约束 |
| RELATIONS | ✅ | Player、Studio、PetPack 三层边界及 provider、GitHub 与历史运行时关系 |
| SPEC | ✅ | PetPack 1.0 行为、ZIP 容器、单一 RGBA 基线、完整性、安全和首版无签名契约已实现；双平台原生装载已实现 |
| ARCHITECTURE | ✅ | 目标组件、固定舞台、多宠状态、双平台新实现与 v0.6.0 历史边界 |
| DIRECTORY | ✅ | 唯一项目根、公开与私有子树、已迁移源码、Studio、宠物事实源、旧包与本地产物边界 |
| DEPLOYMENT | ✅ | 下一代零素材分发目标与 v0.6.0 双平台历史发布基线 |
| PRD | ✅ | 离世客群、定制服务、多宠独立时钟、菜单、隐藏卸载和成功指标 |
| ROADMAP | ✅ | 目录、PetPack、双宠候选和双平台 Player 已完成机械实现，继续真实桌面与同包人工验收 |
| CONVENTIONS | ✅ | 公开私有边界、客户目录、生成配置、慢动作、抠图与包生命周期约定 |
| DECISIONS | ✅ | 追加 ADR-044 至 ADR-052，记录纪念定位、三层架构、目录、PetPack 基线、首版严格边界和执行护栏 |
| MEMORY | ✅ | 追加纯色背景色族、原生慢动作、完整链优先和匹配 Xcode 工具链经验 |
| CHANGELOG | ✅ | 记录 2026-08-23 目录迁移、PetPack 1.0、双宠候选转换、双平台 Player 与逐项验收记录 |

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

同步锚点指向已审阅并提交的 Windows Runner 恶意 ZIP 测试输入修复 `f6b855f`，其对应原始 ZIP 路径安全修复为 `1937a03`，逐项验收记录为 `85d42ab`。首次远端 push 已完成，macOS 工作流通过；PetPack 与 Windows 工作流暴露的两个跨平台测试问题已经在本地修复并等待再次 push 验证。真实 macOS 与 Windows 桌面人工验收、同包视觉与性能一致性、正式交付和 `1.0.0` 发布仍未完成。
