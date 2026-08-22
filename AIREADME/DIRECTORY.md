# DIRECTORY：PetsGraph 项目目录与 Git 边界

> Target: 本文件定义下一代目录结构和迁移护栏。As-built: 公开源码、私有 Studio、宠物事实源、旧包、Codex 工作区与本地产物均已迁入职责目录；PetPack 1.0 公开契约和 macOS Player 已实现，Windows 新行为尚待实现。

## 1. 根目录原则

- `/Users/maxwell/Desktop/Projects/petsgraph` 是整个 PetsGraph 项目的唯一物理根目录。
- Player、PetPack 公开契约、私有 Studio、宠物事实源、PetPack 产物和 Codex 宠物都位于该根目录下。
- 边界通过明确子树、Git 跟踪规则、私有目录和备份策略实现，不把 PetsGraph 资产拆到项目根之外。
- 根 Git 继续承担公开项目历史、Player、公开规范、公开 Codex 宠物、品牌和发布文档。
- `studio/` 是不创建独立 Git 仓库的本机私有目录；根 Git 必须忽略整个 `studio/`，也不得把它记录为 submodule 或 gitlink。
- `pets/` 是宠物素材唯一事实源。`petpacks/` 和 `codexpets/` 只保存面向具体运行时的衍生工作区与交付产物，不复制形成第二套原始资料真相源。

## 2. 目标根目录

```text
petsgraph/
├── player/                     # 公开 Player 源码
│   ├── macos/
│   └── windows/
├── petpack/                    # 公开 PetPack 规范、测试向量与验证器
├── studio/                     # 私有制作工具，不创建独立 .git
├── pets/                       # 私有宠物原始资料与制作事实源
├── petpacks/                   # 私有 PetsGraph 宠物包工作区与交付物
├── codexpets/                  # Codex 宠物公开包、私有包与制作工作区
├── assets/
│   └── brand/                  # 公开品牌资产
├── docs/                       # 面向人的公开文档和历史发布说明
├── AIREADME/                   # 整个项目唯一的 AI 真相源
├── release/
│   └── manifests/              # Player 公开发布清单，不存发布二进制
├── .github/                    # 只访问根 Git 跟踪的公开内容
├── .local/                     # 本机可重建缓存、临时输出和候选发布物
├── README.md
├── ASSETS.md
└── .gitignore
```

根目录不再使用职责不明的长期 `workspaces/`、`output/`、`tmp/` 和 `dist/`。四个旧入口均已在逐项审计、迁移和回读后移除，根 `.gitignore` 不再掩盖它们，误创建会直接出现在 Git 状态中。

## 3. 根公开 Git 的边界

目标根 Git 跟踪：

```text
player/
petpack/
codexpets/README.md
codexpets/packages/public/
codexpets/manifests/public.json
codexpets/fixtures/
codexpets/tools/
assets/brand/
docs/
AIREADME/
release/manifests/
.github/
README.md
ASSETS.md
LICENSE
.gitignore
```

目标根 Git 忽略：

```text
studio/
pets/
petpacks/
codexpets/workspaces/
codexpets/packages/private/
codexpets/manifests/private.json
.local/
.env
.env.*
```

生成服务的安全配置模板与本地真实配置现均位于根 Git 忽略的 `studio/`。根目录不再为 `.env.example` 设置跟踪例外，Player 不需要 provider 环境变量。

公开根 Git 的 CI 不得读取、复制、枚举或假设上述私有目录存在。公开 clone 缺少全部私有目录时，Player、PetPack 验证和公开 Codex 包校验仍必须可以独立执行。

## 4. “Player 零素材”的精确定义

“零素材”只约束 PetsGraph Player，不等于整个项目根 Git 没有任何真实宠物图像：

- `player/` 子树不包含五百、飞流、小葵或客户宠物媒体。
- Player 的 macOS、Windows 安装包不内嵌任何宠物媒体。
- `petpack/fixtures/` 只包含不具有真实宠物身份的合成测试资产。
- `codexpets/packages/public/` 可以版本化保存获得单独公开授权的 Codex 宠物图集。
- Codex 公开图集不进入 Player、Player 安装包或 `.petpack` 测试夹具，也不自动采用 Player 的 MIT License。
- 客户 PetPack、客户 Codex 包、客户原始资料和未公开个人宠物素材始终保持私有。

因此，公开边界必须表述为“Player 子树和 Player 发布物零宠物素材”，不能再笼统写成“整个公开仓库不包含真实宠物素材”。

## 5. `player/`

```text
player/
├── macos/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── PetsGraphV1Core/
│   │   └── PetsGraphV1App/
│   ├── Tests/
│   │   └── PetsGraphV1CoreTests/
│   └── scripts/
└── windows/
    ├── PetsGraph.slnx
    ├── src/
    │   ├── PetsGraph.Core/
    │   ├── PetsGraph.App/
    │   └── PetsGraph.Validator/
    ├── tests/
    └── scripts/
```

- 平台宿主保持原生实现，不强迫 Swift 与 .NET 共用 UI 或渲染代码。
- 两个平台依赖同一份 `petpack/` 契约、测试向量和行为语义。
- 平台构建脚本只产生 `.local/` 中的本机候选，正式公开二进制进入 GitHub Release，根 Git 只保存清单和摘要。

## 6. `petpack/`

```text
petpack/
├── README.md
├── schema/                    # 五份公开 JSON Schema
├── fixtures/
│   ├── README.md
│   └── synthetic-cat-v1.petpack
├── tools/                     # 确定性合成包构建器
├── validator/                 # 标准库参考验证器与 CLI
└── tests/                     # 合法包与动态坏包安全回归
```

- 保存公开、平台无关的 PetPack 契约和安全测试。
- 不保存客户正式包、五百飞流迁移包或小葵候选包。
- 若验证器最终保留多个平台实现，`validator/` 保存参考入口和一致性说明，具体平台代码仍归属 `player/macos/` 与 `player/windows/`。

## 7. `studio/`

```text
studio/
├── providers/
│   ├── seedance/
│   ├── seedream/
│   └── gpt-image/
├── identity/
├── generation/
├── matting/
├── geometry/
├── graph/
├── review/
├── packaging/
├── ledger/
├── native/
├── tests/
├── docs/
├── .env.example
└── .env.local
```

- 保存 provider 适配、提示约束、抠图、固定几何、评审、包编译、未来签名和私有测试。
- 不把大体积宠物媒体复制进 `studio/`；工具通过受控相对路径和清单读取 `pets/`、写入 `petpacks/` 或 `codexpets/workspaces/`。
- `studio/` 不建立独立 Git 历史，工具和配置由本机私有备份保护；根公开 Git 只记录旧公开工作副本的移除，不记录迁入后的内容。
- `.env.local` 只保存真实凭据并由 Studio 自己的忽略规则保护。日志、任务记录和错误不得输出完整凭据或临时签名 URL。
- 不再从其他项目的绝对路径读取 dotenv 或客户数据。跨目录引用必须以 PetsGraph 根目录或显式配置的私有路径为基准。

## 8. `pets/`，唯一宠物事实源

个人宠物：

```text
pets/personal/<pet-id>/
├── meta/
├── source/
├── identity/
├── graph/
├── generation/
│   ├── nodes/
│   └── edges/
├── approved/
├── reviews/
└── archive/
```

客户宠物：

```text
pets/customers/<customer-id>/<pet-id>/
├── meta/
├── source/
├── identity/
├── graph/
├── generation/
│   ├── nodes/
│   └── edges/
├── approved/
├── reviews/
├── archive/
└── retention.json
```

根级辅助目录：

```text
pets/shared/                   # 经授权可复用且不含客户身份的私有制作参考
pets/audit/                    # 迁移、清理、哈希和回读凭据
```

规则：

- `source/` 保存原始输入，不原位修改。
- `generation/` 按节点、边和版本化 attempt 保存生成事实，不用“最终版”“新最终版”等不稳定名字。
- `approved/` 优先保存批准清单、相对路径和摘要，避免无差别复制大媒体；确需冻结副本时必须记录与源 attempt 的哈希关系。
- `archive/` 保存被替代但仍有复用或回滚价值的内容，不与当前候选混放。明确未通过的大型媒体移入系统回收站，只在 `reviews/` 或 `pets/audit/` 保留任务 ID、路径、字节数、摘要、失败原因和评审结论。
- 个人宠物没有客户保留期；客户 `retention.json` 遵守最终交付日起暂定一年的规则。

## 9. `petpacks/`

```text
petpacks/
├── personal/<pet-id>/
│   ├── candidates/
│   ├── approved/
│   ├── delivery/
│   └── archive/
└── customers/<customer-id>/<pet-id>/
    ├── candidates/
    ├── approved/
    ├── delivery/
    └── archive/
```

- 只保存 PetsGraph PetPack 编译输入清单、候选包、正式包、交付副本和迁移历史。
- 原始照片、身份母版和通用生成母片留在 `pets/`，不复制进本目录。
- 正式 `.petpack` 是客户自持交付物；本机 `delivery/` 不是客户长期备份的替代品。
- 客户包、个人未公开包和签名私钥不进入根公开 Git。

## 10. `codexpets/`

```text
codexpets/
├── packages/
│   ├── public/
│   │   ├── wubai-v0/
│   │   │   ├── pet.json
│   │   │   └── spritesheet.webp
│   │   └── feiliu-hatch-native-v1/
│   └── private/
│       └── <customer-id>/<pet-id>/
├── workspaces/
│   └── <pet-id>/
│       ├── selected-frames/
│       ├── generated/
│       ├── layout/
│       ├── qa/
│       └── archive/
├── manifests/
│   ├── public.json
│   └── private.json
├── fixtures/
├── tools/
│   └── manage.py
└── README.md
```

规则：

- 原 `codex-pets/` 已在提交 `76ad2ea` 一次性迁入 `codexpets/`，不保留旧路径兼容入口。
- 当前公开的五百与飞流包位于 `codexpets/packages/public/`，包 ID、媒体字节、摘要、限定授权和 Git 历史保持可追溯。
- `public.json` 只能记录公开包，至少包含 package ID、显示名、字节数、SHA-256、`public=true`、素材所有者和 `licenseRef`。
- `private.json`、私有包和工作区不能被根 Git 跟踪，也不能向公开清单泄漏客户 ID、宠物名、路径或摘要。
- `workspaces/` 只保存 Codex 专用选帧、生成、布局、图集和 QA。输入通过 `pets/` 中的相对路径和内容摘要引用，不复制客户原始资料。
- Codex 结构校验、安装和备份后替换工具进入 `codexpets/tools/`；provider 生成与私有提示仍归 `studio/`。
- Codex 图集的机械通过不继承 PetsGraph PetPack 的连续视频、生命感或运行时批准。

## 11. `.local/`，本机产物与可下载发布副本

```text
.local/
├── cache/
├── tmp/
├── output/
├── dist/
│   ├── builds/
│   └── published/
└── environments/
```

- 新的临时脚本、生成预览、缓存、虚拟环境和候选发布物不再散落到根目录。已发布附件的本地副本位于 `dist/published/`，并以公开 Release 与 manifest 为事实源。
- 只有具备已验证源文件、重建配方和摘要的内容才能归类为可重建。
- 根 `output/`、`tmp/`、`dist/`、`workspaces/`、`.cache/` 与 `.venv*` 均已完成审计并退出。三个 Python 环境和 rembg 模型缓存位于 `.local/`，旧根 Swift `.build/` 缓存位于系统回收站等待用户复查。
- 已成为正式评审证据、获批帧事实源或未上传正式发布物的文件必须进入对应 `pets/`、`petpacks/` 或归档位置。明确失败的大型媒体可以在审计记录完成后移入系统回收站。

## 12. 当前到目标的迁移映射

| 当前 As-built | 目标 Target | 约束 |
|---|---|---|
| `Package.swift`、`Sources/`、`Tests/` | `player/macos/` | 已在 `84bbc5e` 完成；67 项测试迁移前后均通过 |
| `windows/`、`global.json` | `player/windows/` | 已在 `84bbc5e` 完成；7 项测试通过，解决方案 0 警告 0 错误 |
| Player 构建、测试和公开验证工具 | 对应平台 `scripts/` 或 `petpack/validator/` | 不能依赖私有目录也能运行 |
| Seedance、Seedream、抠图、评审和宠物专用工具 | `studio/` | 已在 `6da41e3` 完成公开边界切换；私有内容由根 Git 忽略，不创建独立 Git，不保留公开工作副本 |
| `workspaces/<pet>-private/` | `pets/personal/<pet-id>/` 及 `petpacks/personal/<pet-id>/` | 已在 `90a5a7c` 完成边界切换；事实源与旧包分开，六组文件的 inode 集合、数量和字节数回读一致 |
| 未来客户目录 | `pets/customers/<customer-id>/<pet-id>/` | 客户 ID 稳定且不含姓名，保留期单独记录 |
| `codex-pets/` | `codexpets/packages/public/` | 已在 `76ad2ea` 完成；不保留旧路径兼容 |
| `codex-pets/manifest.json` | `codexpets/manifests/public.json` | 已完成；公开条目增加 `public`、素材所有者和授权指针 |
| `tools/manage-codex-pets.py` | `codexpets/tools/manage.py` | 已完成；安装、校验、冲突拒绝和可恢复备份语义保持 |
| `assets/app-icon/` | `assets/brand/` | 已在 `90bfaa8` 完成；公开定稿哈希不变，7 个候选与 QA 文件迁入私有 `studio/brand/` |
| `output/`、`tmp/`、`.cache/`、`.venv*` | `.local/` 或对应私有事实目录 | 已完成；三套环境有精确依赖快照、导入与命令入口回归，rembg 模型 SHA-256 不变 |
| `dist/`、`workspaces/release-dist/` | `.local/dist/` | 已在 `90a5a7c` 完成边界切换；v0.6.0 双平台附件与 GitHub Release、公开清单摘要一致 |
| `workspaces/cleanup-audits/` | `pets/audit/cleanup/` | 已完成，历史收据和审计清单保持字节不变 |

## 13. 迁移门禁

每个迁移切片必须按以下顺序执行：

1. 记录源路径、职责、文件数、字节数、关键清单与摘要。
2. 判断它是公开源码、私有事实源、正式交付物、历史归档还是已证明可重建的缓存。
3. 创建目标目录和必要忽略规则，但不先删除源目录。
4. 复制或使用可恢复移动完成单一切片，禁止一次性重排整个项目。
5. 回读文件数、字节数、摘要、清单、测试和人工可用性。
6. 确认根 Git 没有跟踪私有前缀，`studio/` 中没有嵌套 `.git`、大媒体副本泄漏或真实凭据进入公开索引。
7. 回读通过后按已确认规则处理旧路径：迁移成功的旧位置可移入系统回收站；失败、重复、缓存和临时产物按审计分类清理，不再逐项请求确认。

建议迁移顺序：

```text
目录与忽略规则
  → 清理审计与回收站迁移
  → codexpets 小型公开包
  → Player 源码与平台测试
  → Studio 工具分类
  → 五百与飞流事实源及 PetPack 工作区
  → 小葵现有私有资料
  → 其他宠物与历史评审
  → 临时目录和发布候选收口
```

五百与飞流已经使用现有批准媒体制作 PetPack 1.0 私有候选，当前位于各自 `candidates/`，没有提前进入 `approved/` 或 `delivery/`；小葵本轮只迁移现有资料，不继续生成、抠图或制作 PetPack。五百、飞流的批准媒体、生产记录和正式包不得因为目录重构被压平或丢失，明确失败的大型媒体则按审计清单移入系统回收站。

## 14. 禁止操作

- 禁止在项目根运行 `git clean -fdx`、`git clean -ffdx` 或其他会递归清理 ignored 内容的命令。
- 禁止重新创建职责不明的根 `workspaces/`，也禁止整体删除、清空或不经清单直接移动 `pets/`、`petpacks/` 与 `codexpets/workspaces/`。
- 禁止把根 `.gitignore` 当作访问控制或备份。私有目录仍需独立权限、私有版本记录和备份。
- 禁止让根 Git 把 `studio/` 记录为 gitlink 或 submodule。
- 禁止让公开 CI 访问本机私有目录、凭据或客户资料。
- 禁止把 `codexpets/packages/public/` 的素材授权扩大为 MIT，或把 private 清单合入 public 清单。
- 禁止在迁移完成前提前修改当前构建、安装和验证命令指向尚不存在的目标路径。

## 15. 当前状态

状态为 `macos-player-implemented / windows-player-next`。

目标目录和 Git 边界已经确认。公开源码、私有 Studio、宠物事实源、旧包、Codex 私有工作区、清理审计、v0.6.0 本地发布副本、Python 环境与模型缓存均已迁移并验证；全部旧根入口已经退出。公开 `petpack/` 已实现 1.0 schema、参考验证器、合成夹具和安全回归。五百与飞流私有候选已经机械验证。macOS Player 已实现原生装载、canonical 库、被动行为、固定舞台和目标菜单，Windows 仍为 v0.6.0 as-built；两个平台的真实桌面验收和正式交付仍待实现。任何后续报告必须逐子树说明实际状态，不能把代码、契约或候选包验证写成桌面视觉已经完成。
