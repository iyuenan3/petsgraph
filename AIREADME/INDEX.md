# PetsGraph · AIREADME
> 面向宠物离世纪念的开源多宠 Player 与私有定制 PetPack 体系 ｜ 生命周期: implementation-in-progress
> last-synced: 35efbca · 2026-08-23
> phase: macos-mechanical-acceptance-partial / windows-gui-deferred

当前公开 `v0.6.0` 仍是内嵌五百与飞流的旧架构发布版。PetPack 1.0 公开 schema、参考验证器、合成包与安全回归已经实现，五百与飞流已经形成私有机械验证候选。Apple Silicon macOS 与 Windows x64 `0.7.0-dev` 均已实现零素材 Player、持久导入激活日志、失败与重启回滚、事务卸载、保守状态恢复、独立行为时钟、固定舞台与目标菜单。Swift 30 项、MSTest 44 项和相关远端运行通过，回归覆盖双宠状态、四边贴靠、透明命中坐标、七档精确标签、卸载中断恢复与 Windows 缓存淘汰；Python、Swift 与 C# 对五百和飞流同一候选包的摘要与图结构结果一致。macOS build 5 已完成双宠首轮真实自主动作链，有界缓存让双宠切换物理峰值为 126.1 MB，进入两个新稳定循环后为 46.7 MB。build 8 已验证低 CPU 路径中的完整自主动作切换，切换后物理占用回落至 29.6 MB。用户已经在 build 14 确认卸载、系统文件关联重新装载、显示、隐藏、目标状态灰显、Dock 区域拖出、上下左右四边贴靠、`0.5` 至 `2.0` 七档全局大小和重启保持成功，内部双宠归档摘要匹配原件。build 15 固化透明命中坐标契约，build 16 修正 `1.25×` 与 `1.75×` 标签，并已完成首次真实启动、唯一进程与资源回读；五百 4 个正常速度画面摘要持续变化，稳定态 CPU 平均约为 0.79%、内存为 52 MB。运行 18 分 34 秒后，飞流按自己的时钟从默认趴卧自主切换至收紧蜷卧，五百保持自己的默认循环，旧飞流循环和过渡媒体均已淘汰，只保留两只当前稳定循环。实际菜单、透明命中、宠物点击无动作和用户正常速度视觉结论仍需人工验收。Windows 真实 GUI 验收按当前要求暂缓。后续报告仍必须显式区分 Target、机械实现、人工验收、候选包与已发布 As-built。

## 状态

| 文件 | 状态 | 摘要 |
|---|:---:|---|
| CORE | ✅ | 纪念陪伴定位、零素材 Player、客户自持 PetPack、私有 Studio 与硬约束 |
| RELATIONS | ✅ | Player、Studio、PetPack 三层边界及 provider、GitHub 与历史运行时关系 |
| SPEC | ✅ | PetPack 1.0 行为、ZIP 容器、单一 RGBA 基线、完整性、安全、首版无签名、状态菜单灰显与 macOS Dock 层级契约已实现；双平台原生装载已实现 |
| ARCHITECTURE | ✅ | 目标组件、固定舞台、多宠状态、包激活事务、双平台新实现、同包机械一致性与 v0.6.0 历史边界 |
| DIRECTORY | ✅ | 唯一项目根、公开与私有子树、已迁移源码、Studio、宠物事实源、旧包与本地产物边界 |
| DEPLOYMENT | ✅ | macOS build 5 至 16 实机与机械证据、Windows 44 项测试和精确倍率标签、同包机械一致性及 v0.6.0 历史基线 |
| PRD | ✅ | 离世客群、定制服务、多宠独立时钟、菜单、隐藏卸载和成功指标 |
| ROADMAP | ✅ | 目录、PetPack、双宠候选、双平台 Player 与同包机械一致性已完成，继续真实桌面视觉验收 |
| CONVENTIONS | ✅ | 公开私有边界、客户目录、生成配置、慢动作、抠图与包生命周期约定 |
| DECISIONS | ✅ | 追加 ADR-044 至 ADR-054，记录纪念定位、三层架构、PetPack 基线、包激活事务、系统临时构建和执行护栏 |
| MEMORY | ✅ | 追加纯色背景色族、原生慢动作、完整链优先、工具链匹配、旧进程识别、帧提交热点、菜单灰显、Dock 层级与回收站恢复边界经验 |
| CHANGELOG | ✅ | 记录 2026-08-23 目录迁移、PetPack 1.0、双宠候选、双平台 Player、build 10 至 16、双平台精确倍率标签、同包机械一致性、资源和完整复验证据 |

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

同步锚点指向 build 16 首次自主换姿证据 `35efbca`，它覆盖首次运行证据 `fe2b37e`、完整重构审计 `b272c85`、Windows 精确倍率标签代码 `0d06e42`、macOS build 16 菜单标签机械验证记录 `46919ce`、精确倍率标签代码 `5fdc03f`、透明命中契约 `d0cc03e`、build 14 边缘大小与重启人工验收 `c0d4011`、资源复验 `09f97b5`、远端验证 `b6a11f5`、位置持久化证据 `2245263`、实际窗口状态回收代码 `901b364`、Dock 拖动人工通过 `d596492`、Build 13 完整复验 `1285550`、Dock 前方窗口层级代码 `c9e9790`、菜单目标状态灰显 `5e7f516`、`.petpack` 系统文件关联 `feaf6cd`、双宠卸载后重新装载与显示隐藏验收 `d402b2d`，并继承装载目录导航 `76856e0`、同包复验 `a4d6761`、build 9 贴边与资源验收 `974f028`、四边贴靠契约 `ded3df1`、有界缓存 `8749ea6`、素材帧率调度 `399fef5`、当前姿态贴边 `cadf095`、计时器直接 tick `cb28c6e` 和帧提交去重 `234e8fe`。远端 macOS 运行 `32637170614`、`32638115738` 与 Windows 运行 `32638713180` 成功。Python、Swift 与 C# 已完成同包机械一致性复验。较早两处清理记录的原始回收站路径目前无法解析，因此只能保留历史移动凭据，不能承诺按原路径恢复；build 15 的精确回收站路径仍可解析。build 16 首次真实启动后唯一进程、签名、摘要、双宠恢复、五百画面变化和稳定态资源回读通过。飞流在运行 18 分 34 秒后自主换姿，五百保持独立循环，回读只剩两只当前稳定循环，证明独立时钟和有界缓存继续生效。菜单灰显、Dock 区域拖出、上下左右四边贴靠、七档大小和重启保持已经用户确认；build 16 的实际菜单、透明命中、宠物点击无动作和明确视觉批准仍未完成。Windows 真实 GUI 验收暂缓，正式交付和 `1.0.0` 发布也尚未完成。
