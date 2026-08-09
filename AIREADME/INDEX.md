# petsgraph · AIREADME
> 面向真实宠物的单宠 macOS 安静桌面陪伴运行时与本地素材包体系 ｜ 生命周期: prototype
> last-synced: 85dd723 · 2026-08-10
> phase: wubai-sleep-companion-mvp

## 状态

| 文件 | 状态 | 摘要 |
|---|:---:|---|
| CORE | ✅ | 李五百睡觉陪伴 MVP、阶段边界与不可违反的质量红线 |
| RELATIONS | ✅ | 生成服务、只读参考项目与未来消费方关系 |
| SPEC | ⚑ | 宠物素材包 v0 草案，新增场景、节点职责、猫体点击区与安静行为契约 |
| ARCHITECTURE | ✅ | 睡眠 MVP 目标架构、当前工程原型差距、动作图与透明窗口数据流 |
| DEPLOYMENT | ⚑ | 本地 macOS 工程原型可运行，睡眠 MVP 尚无可安装版本 |
| PRD | ✅ | 安静睡眠陪伴目标、点击与拖动体验、枕头核心场景和 PM 风险闸门 |
| ROADMAP | ✅ | 先完成普通与枕头睡眠闭环，再做安装与通用素材 Skill |
| CONVENTIONS | ✅ | 睡眠场景、节点职责、素材版本、随机调度与验收约定 |
| DECISIONS | ✅ | 追加睡眠 MVP、枕头网关和质量优先重试策略 |
| MEMORY | ✅ | 素材与运行时事故，以及从能力展示转向安静陪伴的产品复盘 |
| CHANGELOG | ✅ | 睡眠陪伴方向收敛及既有素材、运行时与批准状态记录 |

## 按任务读

- 跨项目了解 → `CORE.md` + `RELATIONS.md`
- 设计或生成宠物素材包 → `SPEC.md` + `CONVENTIONS.md` + `DECISIONS.md`
- 记录或复用已批准素材的生成方法 → `SPEC.md` 第 9.1 节 + `CONVENTIONS.md` + `DECISIONS.md`
- 修改睡眠调度、动作图、播放器或桌面窗口 → `PRD.md` + `ARCHITECTURE.md` + `SPEC.md` + `DECISIONS.md`
- 修改枕头场景、网关或点击坐姿 → `PRD.md` 第 4.5 节 + `SPEC.md` + `DECISIONS.md`
- 讨论产品范围和验收 → `PRD.md` + `ROADMAP.md`
- 安装、运行或发布 → `DEPLOYMENT.md` + `CHANGELOG.md`
- 复盘失败 → `MEMORY.md`，重大取舍另追加到 `DECISIONS.md`
