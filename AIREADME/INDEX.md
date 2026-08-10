# petsgraph · AIREADME
> 面向真实宠物的单宠 macOS 安静桌面陪伴运行时与公开素材包体系 ｜ 生命周期: public-alpha
> last-synced: e80fa09 · 2026-08-10
> phase: low-power-runtime-candidate

## 状态

| 文件 | 状态 | 摘要 |
|---|:---:|---|
| CORE | ✅ | PetsGraph 通用运行时、李五百首发宠物包、阶段边界与质量红线 |
| RELATIONS | ✅ | 生成服务、只读参考项目与未来消费方关系 |
| SPEC | ✅ | 正式 PNG `0.2.0`、HEVC 对照 `0.3.0` 与固定裁剪 RGBA 候选 `0.4.0` 契约 |
| ARCHITECTURE | ✅ | 通用 App、动作图、CALayer、raw mmap、有界预加载、单实例和公开发布边界 |
| DEPLOYMENT | ✅ | Apple 芯片 `0.3.1` 正式发布、raw 候选构建校验、性能测量与非公证边界 |
| PRD | ✅ | 安静睡眠陪伴、朋友安装、指定睡姿、枕头核心场景和 PM 风险闸门 |
| ROADMAP | ✅ | v0.3.1 继续正式分发，下一阶段完成人工低功耗整链验收和通用素材 Skill |
| CONVENTIONS | ✅ | App 与宠物命名、固定 raw crop、单实例、性能测量、Release 和验收约定 |
| DECISIONS | ✅ | 追加固定 clip 裁剪预乘 RGBA、单实例和不提前替换正式包的决策 |
| MEMORY | ✅ | 素材、PNG 体积、HEVC 转换成本、Gatekeeper 重复实例和 macOS 打包事故 |
| CHANGELOG | ✅ | `e80fa09` 低功耗候选、`0.3.1` 通用正式版和既有素材里程碑 |

## 按任务读

- 跨项目了解 → `CORE.md` + `RELATIONS.md`
- 设计或生成宠物素材包 → `SPEC.md` + `CONVENTIONS.md` + `DECISIONS.md`
- 记录或复用已批准素材的生成方法 → `SPEC.md` 第 9.1 节 + `CONVENTIONS.md` + `DECISIONS.md`
- 修改睡眠调度、动作图、播放器或桌面窗口 → `PRD.md` + `ARCHITECTURE.md` + `SPEC.md` + `DECISIONS.md`
- 修改枕头场景、网关或点击坐姿 → `PRD.md` 第 4.5 节 + `SPEC.md` + `DECISIONS.md`
- 讨论产品范围和验收 → `PRD.md` + `ROADMAP.md`
- 安装、运行或发布 → `DEPLOYMENT.md` + `CHANGELOG.md`
- 复盘失败 → `MEMORY.md`，重大取舍另追加到 `DECISIONS.md`
