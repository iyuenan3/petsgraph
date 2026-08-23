# PetsGraph · AIREADME
> 面向宠物离世纪念的开源多宠 Player 与私有定制 PetPack 体系 ｜ 生命周期: release-frozen
> last-synced: 9bea548 · 2026-08-23
> phase: v1.0.0-source-and-artifacts-frozen / windows-gui-deferred

PetPack 1.0 公开 schema、参考验证器、合成包与安全回归已经实现。Apple Silicon macOS 与 Windows x64 `1.0.0` 零素材 Player 源码已冻结在注解标签 `v1.0.0`，标签指向 `b98a3bf`；双平台清单提交 `9bea548` 已固定一个 macOS arm64 DMG 和一个 Windows x64 ZIP。Swift 33 项、MSTest 45 项、WPF 零警告构建、双平台格式与零素材检查通过。用户已经验收 macOS 双宠正常速度、独立换姿、拖动、四边贴靠、大小、重启、菜单和透明命中；双宠 60 秒稳定态样本平均 CPU 约 0.74%，物理内存 64.7 MB。Windows 真实 GUI 本轮未复验，五百与飞流继续保持私有候选。当前状态是本地附件与发布契约已冻结，GitHub Release 尚未公开，后续报告必须区分源码冻结、附件冻结、公开发布、平台机械验证和人工验收。

## 状态

| 文件 | 状态 | 摘要 |
|---|:---:|---|
| CORE | ✅ | 纪念陪伴定位、零素材 Player、客户自持 PetPack、私有 Studio 与硬约束 |
| RELATIONS | ✅ | Player、Studio、PetPack 三层边界及 provider、GitHub 与历史运行时关系 |
| SPEC | ✅ | PetPack 1.0 行为、ZIP 容器、单一 RGBA 基线、完整性、安全、状态菜单灰显、关于窗口与 macOS Dock 层级契约已实现 |
| ARCHITECTURE | ✅ | 目标组件、固定舞台、多宠独立时钟、macOS 共享调度与隐藏资源释放、包激活事务、双平台新实现和历史边界 |
| DIRECTORY | ✅ | 唯一项目根、公开与私有子树、已迁移源码、Studio、宠物事实源、旧包与本地产物边界 |
| DEPLOYMENT | ✅ | v1.0.0 标签与双附件冻结、macOS build 5 至 19 证据、Windows 45 项测试、零素材边界及 v0.6.0 历史基线 |
| PRD | ✅ | 离世客群、定制服务、多宠独立时钟、菜单、隐藏卸载和成功指标 |
| ROADMAP | ✅ | 目录、PetPack、双宠候选、双平台 Player 与 v1.0.0 本地冻结已完成，继续公开 Release 与远端复验 |
| CONVENTIONS | ✅ | 公开私有边界、客户目录、生成配置、慢动作、抠图与包生命周期约定 |
| DECISIONS | ✅ | 追加 ADR-044 至 ADR-056，记录纪念定位、三层架构、PetPack 基线、共享调度与 v1.0.0 零素材双附件发布边界 |
| MEMORY | ✅ | 追加纯色背景色族、原生慢动作、完整链优先、工具链匹配、旧进程识别、帧提交热点、菜单灰显、Dock 层级与回收站恢复边界经验 |
| CHANGELOG | ✅ | 记录 2026-08-23 目录迁移、PetPack 1.0、双平台 Player、build 10 至 19 与 v1.0.0 冻结证据 |

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

同步锚点指向 `9bea548` 的 v1.0.0 双平台发布清单。源码标签 `v1.0.0` 固定在 `b98a3bf`，继承 build 18 人工使用结论、build 17 共享调度、build 16 完整 macOS 验收，以及 PetPack 1.0、双平台原生 Player、透明命中、Dock 层级、四边贴靠、倍率标签和事务恢复证据。本机已经冻结并复验两个零素材附件，GitHub Release 公开状态和远端下载摘要仍需下一阶段回读。Windows 真实 GUI 本轮未复验，不能由 45 项测试、WPF 构建或 AMD64 ZIP 替代。
