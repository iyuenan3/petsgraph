# petsgraph · AIREADME
> 面向真实宠物的单宠 macOS 桌面陪伴运行时与本地素材包体系 ｜ 生命周期: prototype
> last-synced: c39dd1a · 2026-08-09
> phase: phase-0-materials

## 状态

| 文件 | 状态 | 摘要 |
|---|:---:|---|
| CORE | ✅ | 产品身份、阶段边界与不可违反的质量红线 |
| RELATIONS | ✅ | 生成服务、只读参考项目与未来消费方关系 |
| SPEC | ⚑ | 宠物素材包 v0 草案，待首条真实动作链验证后定稿 |
| ARCHITECTURE | ⚑ | 目标组件、动作图运行时与 root motion 数据流，技术栈待原型选择 |
| DEPLOYMENT | ⚑ | 第一阶段本地 macOS 运行，尚无可安装版本 |
| PRD | ✅ | 产品目标、第一阶段范围、成功指标和 PM 风险闸门 |
| ROADMAP | ✅ | 先验证单宠移动闭环，再扩姿态与素材 Skill |
| CONVENTIONS | ✅ | 动作、方向、素材版本与验收记录约定 |
| DECISIONS | ✅ | 已确认的产品与技术 ADR |
| MEMORY | ✅ | 画布边界失败、后脚滑步漏检与对应避免规则 |
| CHANGELOG | ✅ | 立项、右向站走动作批准、过渡策略演进与批准素材生产履历 |

## 按任务读

- 跨项目了解 → `CORE.md` + `RELATIONS.md`
- 设计或生成宠物素材包 → `SPEC.md` + `CONVENTIONS.md` + `DECISIONS.md`
- 记录或复用已批准素材的生成方法 → `SPEC.md` 第 9.1 节 + `CONVENTIONS.md` + `DECISIONS.md`
- 修改动作图、播放器或桌面窗口 → `ARCHITECTURE.md` + `SPEC.md` + `DECISIONS.md`
- 讨论产品范围和验收 → `PRD.md` + `ROADMAP.md`
- 安装、运行或发布 → `DEPLOYMENT.md` + `CHANGELOG.md`
- 复盘失败 → `MEMORY.md`，重大取舍另追加到 `DECISIONS.md`
