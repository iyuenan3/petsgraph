# PetsGraph Player for Windows x64

> 当前 main 是 `0.7.0-dev` 开发实现，使用 PetPack 1.0，发布物不包含任何真实宠物素材。当前公开可下载版本仍是历史 `v0.6.0`，它内嵌五百和飞流并保留旧交互。历史安装与回滚事实见 [DEPLOYMENT](../../AIREADME/DEPLOYMENT.md)。

## 开发版使用方式

1. 完整解压 `PetsGraph-v0.7.0-dev-Windows-x64.zip`，不要只拖出 `PetsGraph.exe`。
2. 双击 `PetsGraph.exe`。程序可以在没有宠物时启动，控制入口位于系统托盘。
3. 右键托盘图标，选择“装载宠物包…”，可以一次选择一个或多个 `.petpack`。
4. 装载成功后，PetsGraph 使用自己的内部副本。用户可以把原始 `.petpack` 移到云盘、移动硬盘或其他长期保存位置。
5. 宠物只按各自的时钟自主活动。按住可见主体可以拖动位置，单击不会触发动作。

托盘菜单只包含：

- 装载宠物包。
- 按全部或单只显示宠物。
- 按全部或单只隐藏宠物。
- 按全部或单只卸载宠物。
- 全局 `0.5` 至 `2.0` 七档大小。
- 退出 PetsGraph。

隐藏保留 Player 内部宠物包和位置，适合会议投屏。卸载会删除内部包、cache、位置和显示状态，恢复时必须重新提供原始 `.petpack`。

## 本地数据

Windows 数据根为 `%LOCALAPPDATA%\PetsGraph\`：

```text
library/       不可变 canonical PetPack
cache/         可从 canonical PetPack 重建的运行时文件
registry.json  已装载宠物索引
settings.json  全局大小、每宠位置和显示状态
```

升级 Player 只能替换应用目录和可重建 cache，不能修改 `library/`。普通删除应用目录不会自动删除已装载宠物。

## 离线校验

开发包可以在 PowerShell 中验证任意 PetPack，不需要先装载：

```powershell
$process = Start-Process .\PetsGraph.exe -ArgumentList "--validate-only", "D:\Pets\my-pet.petpack" -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "PetsGraph validation failed: $($process.ExitCode)" }
```

校验覆盖 ZIP 与 ZIP64 边界、store 与 deflate、安全路径、严格 JSON、完整性、媒体长度、动作图和首尾帧渲染。成功输出不包含宠物显示名或本机完整路径。

## 当前验收边界

`.NET 10` 核心测试、WPF 交叉编译、公开合成包以及五百和飞流真实候选的原生校验已经通过。真实 Windows 11 x64 上的透明命中、DPI、拖动、托盘、多显示器、隐藏恢复、升级保留和长时间视觉验收仍是正式发布前的人类闸门。

当前开发包没有代码签名，Windows 可能显示 SmartScreen 提示。只运行来源和摘要已经核对的构建物。
