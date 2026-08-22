# CONVENTIONS：PetsGraph

## 命名

- 品牌统一使用 `PetsGraph Player`，应用名可以保持 `PetsGraph`。macOS Bundle ID 当前为 `com.maxwell.petsgraph`，Windows 主程序为 `PetsGraph.exe`。
- 客户交付文件使用 `<package-id>.petpack`。一个包只包含一只宠物。
- package ID、pet ID、目录和内部文件使用稳定小写英文 kebab-case，不使用客户姓名或可识别个人信息。
- `contentVersion` 使用语义化版本。已交付正式包不可原位覆盖，修订版提升版本并保留旧交付记录。
- 动作图节点使用层级点号，例如 `rest.floor.primary`、`rest.bed.curled`、`activity.window.watch`。
- clip ID 使用 `<source>-to-<target>-v<n>` 或 `<state>-loop-v<n>`，有向语义必须从名称和清单同时可读。
- 方向使用完整单词 `left`、`right`、`front`，不使用单字母缩写。
- 用户界面只显示包内 `pet.displayName`，不显示节点 ID、clip ID、版本或内部状态。

## 公开与私有边界

项目物理根固定为 `petsgraph/`，详细目录、根 Git 跟踪范围和迁移门禁以 `DIRECTORY.md` 为准。

公开 `player/`、`petpack/` 与根 Git 可以包含：

- Player 源码、PetPack 规范、验证器、合成测试包、坏包样例、构建和发布流程。
- 不具有真实宠物身份的最小测试媒体。
- 单独授权的 `codexpets/packages/public/`、公开清单和安全安装校验工具。
- Player 不需要 provider 环境变量。生成服务的变量名与安全占位模板只位于根 Git 忽略的 `studio/.env.example`。

私有 Studio 必须保存：

- 客户原始照片、视频、说明和授权。
- 五百、飞流、小葵和客户的未公开母片、未来 PetPack 正式媒体及生产履历。已经随历史版本公开的五百、飞流素材继续遵守 `ASSETS.md`，不因仓库重构扩大授权。
- Seedance、Seedream、GPT Image 生成工具、提示词、任务账本和评审证据。
- 抠图、几何锁定、包编译、签名和交付工作区。

`studio/` 由根 Git 完整忽略，不创建独立 Git 仓库。不得因为它没有版本历史而把制作工具复制回公开目录；本机备份责任与公开源码提交分开。

公开代码的 MIT License 不自动扩展到五百、飞流、小葵或客户素材。历史公开素材边界见 `ASSETS.md`，客户 `.petpack` 以单独交付约定为准。

## 客户目录

建议私有目录结构：

```text
pets/customers/
  <customer-id>/
    <pet-id>/
      source/
      identity/
      generation/
      reviews/
      production/
      delivery/
      retention.json
```

- `retention.json` 记录最终交付日、暂定到期日、客户授权范围和是否允许展示。
- 默认保留期从最终交付日起一年，正式接单前补充到期删除、提醒、延期和再次交付规则。
- 客户资料不进入 Git、AIREADME、公开测试包、普通日志或第三方训练集。

## 本机生成配置

- Ark 基础地址使用 `ARK_BASE_URL`。
- Seedance 提交、轮询和近期任务回读只读取 `SEEDANCE_API_KEY`；第二把独立凭证为 `SEEDANCE_API_KEY_2`，当前不自动轮换。
- Seedream 静态任务只读取 `SEEDREAM_API_KEY`。
- 同时拥有 Seedance 与 Seedream 权限的凭证使用 `SEEDANCE_SEEDREAM_API_KEY`，当前不自动替代专用凭证。
- GPT Image 使用 `GPT_IMAGE_API_KEY` 与 `GPT_IMAGE_API_KEY_2`，具体工具若只支持一把凭证必须明确记录，不静默混用。
- 历史 `ARK_API_KEY`、`ARK_API_KEY_BAK` 和 `GPT_IMAGE_API_KEY2` 已停用。工具检测到旧名称时给出迁移错误，不静默回退。
- 真实值只存在于被 Git 忽略的 `studio/.env.local`；`studio/.env.example` 只记录变量名和安全占位。迁移完成后不再读取根 `.env.local` 或其他项目的配置。
- 工具使用受控 dotenv 解析器，不通过 Shell `source .env.local`，也不输出完整环境或 Authorization 头。

## 素材生产偏好

- 先建立身份母版和生活习惯证据，再设计该宠物的节点、场景和有向边。
- 优先生成较长的连续生活链，再在稳定帧、完整呼吸边界、自然遮挡或完全离场处确定性切出 loop 和 transition。
- 每条反向边独立生成和验收，不使用正向倒放、镜像或淡入淡出。
- 呼吸、醒来、起身、趴下、吃饭、舔毛等动作按最终慢速原生生成，正式播放倍率保持 `1.0x`。
- 每次生成必须说明相对上一版改变的假设、端点、动作分解、画布或提示约束。禁止无差别批量抽卡。
- 结果未知时查询原任务，不自动重新提交；任务 ID、输入摘要、输出摘要和人工结论进入私有履历。
- 静态图只用于身份、姿态和画布参考，不能直接获得动作、接缝或运行时批准。
- 正常速度观看是首要人工闸门。慢放和机械指标用于定位问题，不替代主人“像它、自然、连贯”的判断。

## 抠图与固定几何

- Seedance 的纯色背景按整段颜色族处理，不假设每帧等于一个固定 RGB。
- 同一 clip 使用统一背景采样、颜色距离、主体连通性和去色溢参数，避免逐帧 Alpha 闪烁。
- 若源视频包含无法稳定消除的纹理、移动阴影、地面线或背景主体，应拒绝母片。
- 未抠图单段与完整图先通过身份、动作、端点和接缝验收，再统一抠图。
- 粗抠通过后锁定每条 clip 的整段缩放和平移。精抠只修改 Alpha 和边缘颜色，不能根据新包围盒重新定位。
- 已经干净且接缝通过的媒体逐字节复用，不能为了统一算法无差别重做。

## Player 与 PetPack 偏好

- Player 把 `.petpack` 导入内部 canonical 库，不引用用户外部路径。
- canonical copy 不可变，cache 可重建，应用更新不触碰 canonical 库。
- 包更新先完整验证再原子替换，任何失败保留旧版。
- 每只宠物独立时钟、位置、可见状态和媒体缓存；所有宠物共享一个全局倍率。
- 固定舞台不读取 root motion 驱动桌面窗口。拖动只改变用户设置的底部中心锚点。
- 行为只沿动作图和批准边运行，预加载失败停留在当前稳定循环。
- 菜单项与状态由已装载包动态派生，不写死具体宠物。

## 文档与证据

- 所有文档明确区分 Target、As-built、Historical 与 Review-only。
- 机械验证、源素材人工通过、透明整链通过、双平台运行时通过和客户交付批准是不同状态，不能互相代替。
- AIREADME 的 DECISIONS、MEMORY 和 CHANGELOG 只追加，不改写历史。
- 当前代码、测试和发布物与目标架构冲突时，文档同时记录差距，不把计划写成已经实现。
- 中文文档不使用破折号字符，改用逗号、句号、冒号或括号。
- 重构直接在 `main` 上按单一职责小步提交，使用精确路径暂存并在每个验证通过的切片后及时 push；不得把用户无关改动、私有工具或临时产物混入公开提交。
- 明确失败的大型媒体、字节完全重复文件和可重建缓存先记录路径、字节数、摘要与原因，再移入系统回收站，不逐项请求二次确认。小型任务记录、失败原因和评审结论继续保留。

## 禁用模式

- 禁止把骨骼、精灵图、肢体拼接、RIFE、光流、自动补间、跨节点倒放或交叉淡化混入正式素材。
- 禁止生成快速动作后通过降速、抽帧、复制帧或帧混合补救。
- 禁止随机视频数组、固定播放列表和没有有向边的硬切。
- 禁止 Player 提供点击动作、睡姿选择、动作菜单或窗口随视频移动。
- 禁止为每只宠物提供独立大小设置，或在全局缩放时改变宠物包基础体型。
- 禁止把多个宠物、多个时钟或跨宠关系塞进一个 `.petpack`。
- 禁止让隐藏宠物在 Player 重启后自动出现。
- 禁止卸载时保留一个无法解释的半注册包，或删除用户外部 `.petpack`。
- 禁止把正式宠物媒体嵌入下一代 Player 发布包。
- 禁止在仓库、日志、宠物包或文档中写入 provider 凭据、客户 PII、签名 URL 或完整认证头。
- 禁止把 PetPack 官方签名实现成联网 DRM 或订阅锁。
- 禁止让 Codex 图集进入 PetsGraph PetPack 加载器，或把其固定图集机械通过写成连续视频生命感通过。
- 禁止在项目根执行 `git clean -fdx`、`git clean -ffdx` 或同类递归清理 ignored 内容的命令。
- 禁止整体删除、清空或不经清单直接移动 `workspaces/`、`pets/`、`petpacks/`、`codexpets/workspaces/` 和 `codexpets/packages/private/`。
