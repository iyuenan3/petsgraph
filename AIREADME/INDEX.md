# PetsGraph · AIREADME
> 面向宠物离世纪念的开源多宠 Player 与私有定制 PetPack 体系 ｜ 生命周期: implementation-in-progress
> last-synced: 70062d8 · 2026-08-23
> phase: macos-mechanical-acceptance-partial / windows-gui-deferred

当前公开 `v0.6.0` 仍是内嵌五百与飞流的旧架构发布版。PetPack 1.0 公开 schema、参考验证器、合成包与安全回归已经实现，五百与飞流已经形成私有机械验证候选。Apple Silicon macOS 与 Windows x64 `0.7.0-dev` 均已实现零素材 Player、持久导入激活日志、失败与重启回滚、事务卸载、保守状态恢复、独立行为时钟、固定舞台与目标菜单。Swift 25 项、MSTest 43 项和相关远端运行通过，回归覆盖双宠状态、卸载中断恢复与 Windows 缓存淘汰。macOS build 5 已完成双宠首轮真实自主动作链，有界缓存让双宠切换物理峰值为 126.1 MB，进入两个新稳定循环后为 46.7 MB。当前已安装 build 8，默认双宠稳定态十次 CPU 取样平均为 0.97%，物理占用约 54 至 55 MB；图像摘要持续变化，但状态栏菜单、真实拖动、卸载语义和用户正常速度视觉结论仍需人工验收。Windows 真实 GUI 验收按当前要求暂缓。后续报告仍必须显式区分 Target、机械实现、人工验收、候选包与已发布 As-built。

## 状态

| 文件 | 状态 | 摘要 |
|---|:---:|---|
| CORE | ✅ | 纪念陪伴定位、零素材 Player、客户自持 PetPack、私有 Studio 与硬约束 |
| RELATIONS | ✅ | Player、Studio、PetPack 三层边界及 provider、GitHub 与历史运行时关系 |
| SPEC | ✅ | PetPack 1.0 行为、ZIP 容器、单一 RGBA 基线、完整性、安全和首版无签名契约已实现；双平台原生装载已实现 |
| ARCHITECTURE | ✅ | 目标组件、固定舞台、多宠状态、包激活事务、双平台新实现与 v0.6.0 历史边界 |
| DIRECTORY | ✅ | 唯一项目根、公开与私有子树、已迁移源码、Studio、宠物事实源、旧包与本地产物边界 |
| DEPLOYMENT | ✅ | macOS build 5 动作链与缓存证据、build 8 安装态资源 A/B、下一代零素材分发目标及 v0.6.0 历史基线 |
| PRD | ✅ | 离世客群、定制服务、多宠独立时钟、菜单、隐藏卸载和成功指标 |
| ROADMAP | ✅ | 目录、PetPack、双宠候选和双平台 Player 已完成机械实现，继续真实桌面与同包人工验收 |
| CONVENTIONS | ✅ | 公开私有边界、客户目录、生成配置、慢动作、抠图与包生命周期约定 |
| DECISIONS | ✅ | 追加 ADR-044 至 ADR-054，记录纪念定位、三层架构、PetPack 基线、包激活事务、系统临时构建和执行护栏 |
| MEMORY | ✅ | 追加纯色背景色族、原生慢动作、完整链优先、工具链匹配、旧进程识别与帧提交热点经验 |
| CHANGELOG | ✅ | 记录 2026-08-23 目录迁移、PetPack 1.0、双宠候选、双平台 Player、缓存贴边与 build 8 资源证据 |

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

同步锚点指向 build 8 资源优化验收 `70062d8`，它覆盖有界缓存 `8749ea6`、素材帧率调度 `399fef5`、当前姿态贴边 `cadf095`、计时器直接 tick `cb28c6e` 和帧提交去重 `234e8fe`，并继承恢复加固 `c48cf52`、构建 4 内存修复 `9befad5`、PetPack 加固 `8b8f902`、Player 事务安全 `b417a6b`、CodexPets 原子安装 `47608a0` 和历史 Release 只读验证 `bbe8997`。远端运行 `32627927411`、`32627927365`、`32629083181` 与 `32630596224` 成功。四边拖动、菜单、卸载和明确视觉批准仍未完成，Windows 真实 GUI 验收暂缓，正式交付和 `1.0.0` 发布也尚未完成。
