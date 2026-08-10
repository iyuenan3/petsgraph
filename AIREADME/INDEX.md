# petsgraph · AIREADME
> 面向真实宠物的单宠 macOS 安静桌面陪伴运行时与公开素材包体系 ｜ 生命周期: public-alpha
> last-synced: 82921d8 · 2026-08-10
> phase: petsgraph-public-release-v0.3.1

## 状态

| 文件 | 状态 | 摘要 |
|---|:---:|---|
| CORE | ✅ | PetsGraph 通用运行时、李五百首发宠物包、阶段边界与质量红线 |
| RELATIONS | ✅ | 生成服务、只读参考项目与未来消费方关系 |
| SPEC | ✅ | 已实现的宠物素材包 `0.2.0` schema、中文显示名、场景、节点职责、猫体点击区与安静行为契约 |
| ARCHITECTURE | ✅ | 通用 App 与宠物包分层、睡眠动作图、指定睡姿队列、透明窗口与公开发布数据流 |
| DEPLOYMENT | ✅ | Apple 芯片 `0.3.1` PetsGraph DMG、四附件发布、构建校验与非公证边界 |
| PRD | ✅ | 安静睡眠陪伴、朋友安装、指定睡姿、枕头核心场景和 PM 风险闸门 |
| ROADMAP | ✅ | 通用品牌版本已就绪，下一阶段验证真实安装、减包实验和通用素材 Skill |
| CONVENTIONS | ✅ | App 与宠物命名、中文 UI、睡眠场景、四附件 Release 和验收约定 |
| DECISIONS | ✅ | 追加通用 App 品牌、内置宠物分层、四附件 Release 和受验证发布策略 |
| MEMORY | ✅ | 素材、运行时、PNG 体积与 macOS 打包事故，以及安静陪伴产品复盘 |
| CHANGELOG | ✅ | `0.3.1` 通用 PetsGraph 版本、四附件发布和既有素材里程碑 |

## 按任务读

- 跨项目了解 → `CORE.md` + `RELATIONS.md`
- 设计或生成宠物素材包 → `SPEC.md` + `CONVENTIONS.md` + `DECISIONS.md`
- 记录或复用已批准素材的生成方法 → `SPEC.md` 第 9.1 节 + `CONVENTIONS.md` + `DECISIONS.md`
- 修改睡眠调度、动作图、播放器或桌面窗口 → `PRD.md` + `ARCHITECTURE.md` + `SPEC.md` + `DECISIONS.md`
- 修改枕头场景、网关或点击坐姿 → `PRD.md` 第 4.5 节 + `SPEC.md` + `DECISIONS.md`
- 讨论产品范围和验收 → `PRD.md` + `ROADMAP.md`
- 安装、运行或发布 → `DEPLOYMENT.md` + `CHANGELOG.md`
- 复盘失败 → `MEMORY.md`，重大取舍另追加到 `DECISIONS.md`
