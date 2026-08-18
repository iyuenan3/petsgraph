# PetsGraph for Windows

这个版本面向 Windows 11 x64，采用免安装便携包，不使用 MSIX，也不包含代码签名。

## 使用

1. 解压完整 ZIP，不要只拖出 `PetsGraph.exe`。
2. 双击 `PetsGraph.exe`。
3. PetsGraph 会在系统托盘显示双猫图标，右键图标可以分别显示或隐藏宠物、选择睡姿、调整大小或退出。
4. 点击睡眠中的宠物会让它起身坐好，再次点击会回去睡觉。按住宠物可以拖动位置。

程序和 `Pets` 文件夹必须保持在同一目录。设置保存在 `%LOCALAPPDATA%\PetsGraph\settings.json`。

## Windows 安全提示

内部版本没有代码签名。Windows 可能显示 SmartScreen 提示，请只使用由项目成员通过 GitHub Release 分享的 ZIP，并在需要时核对 SHA-256。

## 离线校验

PowerShell 中运行并等待校验完成：

```powershell
$process = Start-Process .\PetsGraph.exe -ArgumentList "--validate-only", "--verify-integrity" -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "PetsGraph validation failed: $($process.ExitCode)" }
```

该命令会检查宠物包契约、人工审批状态、媒体长度、首尾帧可渲染性和 SHA-256 完整性。
