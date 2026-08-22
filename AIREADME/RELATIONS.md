# RELATIONS：PetsGraph

## 出向依赖（我用了谁）

PetsGraph Player 的目标运行时完全离线，不依赖账号、数据库、分析平台、素材生成 API 或持续在线服务。

| 依赖 | 用途 | 边界 |
|---|---|---|
| Seedance | 私有制作侧生成连续生活视频、稳定循环和有向过渡 | 不进入公开 Player、`.petpack` 或客户运行环境；正式素材仍需正常速度人工验收 |
| Seedream 与 `gpt-image-2` | 私有制作侧建立身份母版、姿态参考和安全画布 | 只提供静态参考，不能代替连续动作、接缝或运行时批准 |
| 本地抠图与包编译工具 | 背景色族建模、去色溢、固定几何、完整性和 PetPack 编译 | 保持私有；不向 Player 暴露 provider、提示词、客户源资料或生产目录 |
| GitHub | 开源 Player、PetPack 规范、单独授权的公开 Codex 宠物与当前桌面发布物分发 | 不是运行时依赖，不承载客户原始资料、私有 Studio、客户 `.petpack` 或私有 Codex 包 |

本机生成服务的变量命名和凭据边界见 `CONVENTIONS.md`。任何真实值都只存在于被 Git 忽略的本机配置中。

## 只读参考项目

- `mochi-master` 只读参考透明桌面窗口、内容寻址和制作侧分层，不继承其平面动作表、硬切或动态 WebP 唯一路线。
- `petsdesk` 是历史前任项目，只用于复盘窗口交互、root motion 与素材路线；新目标不复用其自主巡游和通用桌面宠物产品边界。

## 入向（谁用我）

- 当前公开 `v0.6.0` 的 Swift/AppKit 与 .NET/WPF 宿主仍内嵌五百和飞流 schema `0.4.0` 包，这是历史已发布事实，不是下一代分发目标。
- 下一代 Apple Silicon macOS 与 Windows x64 PetsGraph Player 将消费平台无关 `.petpack`，一包一宠，一个 Player 可同时装载多个包。
- 客户自行保留 `.petpack`，装载后 Player 使用内部副本。Player 升级不得损坏或改写已装载正式包。
- 第三方可以按公开 PetPack 规范制作合规包；首个 1.0 不带签名，未来 Maxwell 官方定制包可以用后续格式的签名表明来源和质量流程，但不通过签名限制离线使用。
- 当前没有其他项目把 PetsGraph 当作代码或服务依赖。

## 三层产品边界

```text
私有 Studio
  客户资料、生成、抠图、评审、编译
              ↓
       客户自持 .petpack
              ↓
公开 PetsGraph Player
  装载、校验、播放、显示隐藏、卸载
```

`player/` 子树和 Player 发布物只保留格式规范、校验器和不含真实宠物身份的合成测试资产。项目根 Git 的 `codexpets/packages/public/` 可以保存单独授权的公开 Codex 图集，但客户资料、正式 PetPack 媒体、私有 Codex 包和生产工具不因 Player 开源而获得公开授权。完整目录边界见 `DIRECTORY.md`。

## 共享底座 / 复用资产

暂无跨项目共享服务或公共基础设施。未来如果拆出独立 PetPack 校验库，先确定属主项目，再在此只保留到属主 `AIREADME/` 的指针。
