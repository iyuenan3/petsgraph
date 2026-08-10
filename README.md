# PetsGraph

PetsGraph 是一个面向真实宠物的开源 macOS 桌面陪伴运行时。当前首发包内置李五百，让它在你的桌面上安静睡觉、翻身，并偶尔换一个舒服的姿势。

[下载 Apple 芯片 Mac 安装包](https://github.com/iyuenan3/petsgraph/releases/download/v0.3.1/PetsGraph-v0.3.1-macOS-arm64.dmg) · [查看 v0.3.1 发布说明](https://github.com/iyuenan3/petsgraph/releases/tag/v0.3.1)

![李五百的十种睡姿](https://github.com/iyuenan3/petsgraph/releases/download/v0.3.1/Wubai-Sleep-Postures-v0.3.1.png)

## 安装

当前公开版本只支持 Apple 芯片 Mac，需要 macOS 14 或更高版本。

1. 下载并打开 DMG。
2. 把 `PetsGraph.app` 拖入 `Applications`。
3. 第一次启动时，如果 macOS 阻止打开，请在 Finder 中右键 App 并选择「打开」。也可以前往「系统设置 > 隐私与安全性」确认打开。

当前 App 使用 ad-hoc 签名，没有 Developer ID 签名和 Apple 公证，所以首次打开会出现安全提示。应用不需要联网，不上传照片，不连接素材生成服务，也不收集遥测数据。

## 当前内置宠物：李五百

### 怎么陪它

- 李五百启动后默认出现在屏幕左下角，大部分时间安静睡觉。
- 点击睡眠中的李五百，它会沿动作图醒来并正面坐好。
- 再次点击，它会自然回去睡觉。
- 可以把它拖到桌面的任意位置，它会保持在普通窗口和 Dock 前方。
- 菜单顶部显示「当前宠物：李五百」。
- 「选择睡姿」可以直接指定一种睡姿。
- 正在播放不可中断动作时，新的睡姿选择会排队，完成当前动作后自然切换，不会硬切画面。

十种可选睡姿：

- 普通睡姿：趴卧、左侧蜷卧、左侧伸展、仰卧、蜷缩仰卧、松散半仰卧、睡眠香箱。
- 枕头睡姿：头趴枕头、紧凑半仰卧、整身蜷睡。

App 名称、运行时和宠物身份已经分离。以后增加其他宠物时，App 仍然叫 `PetsGraph`，菜单和反馈从宠物包读取宠物名称。

## 为什么是睡觉陪伴

PetsGraph 最初验证过走路、跑步和真实桌面位移。真正长时间使用后，我们发现最舒服的体验并不是让宠物完成任务，而是偶尔抬眼就能看见熟悉的宠物在桌面角落安心睡觉。

因此第一个版本只做安静陪伴。已完成的走跑素材与 root motion 工程能力继续保留，但不进入公开版的默认行为。

## 动作不是随机硬切

每个稳定姿态是节点，循环动作和有向过渡是边。运行时只在安全退出帧离开循环，提前加载下一条边，并逐帧播放完整过渡。例如：

```text
趴卧
  → 左侧蜷卧
  → 左侧伸展
  → 仰卧
  → 返回趴卧
```

带枕头的睡眠属于完整场景。枕头只通过已经验收的进出场动作出现或离开，并在场景内保持位置、尺度和接触关系连续。

## 为什么安装包比较大

v0.3.1 内置 53 个逐帧动作片段、6,866 个运行时帧和约 286 秒动画。App 中约 465 MB 的内容是已经批准的透明 PNG 素材，主程序本身约 1 MB。

PNG 已经压缩，再套 ZIP 或 DMG 只能小幅缩减，所以 DMG 仍有约 454 MiB。Release 不再重复上传独立 `.petsgraph-pet`，普通用户只需要下载 DMG。

main 分支已经完成一套低功耗候选格式：保留获批 PNG 作为制作事实源，把运行时副本编译成每条动作统一固定裁剪的预乘 RGBA 媒体。它用约 1.827 GB 存储换取更低的长期运行成本，真实桌面普通睡眠约占 1.3% 到 1.6% CPU 和 53 MiB 内存，连续换姿约占 2.1% 到 2.7% CPU 和 19 到 46 MiB 内存。该候选仍等待完整人工视觉验收，因此尚未替换 v0.3.1 Release，也不会为了性能修改获批源帧。

## 验证状态

- 53 个逐帧动作片段。
- 14 个姿态节点和 39 条有向边。
- 7 种普通睡姿、3 种枕头睡姿和两个场景坐姿。
- 6,925 条文件完整性记录。
- v0.3.1 Release 通过 45 项 XCTest。当前 main 分支通过 57 项 XCTest，新增低功耗媒体完整性、媒体哈希、异常隐藏、单实例保护和运行时媒体回归。
- 正式 v0.3.1 的获批素材帧与 v0.3.0 逐项哈希一致，没有重新生成、抠图或修改源帧。

正式 App 和素材随 [GitHub Release](https://github.com/iyuenan3/petsgraph/releases) 分发，不把数百 MB 的运行时资源写入 Git 历史。原始宠物照片、Seedance 任务记录、被拒绝的候选和私有生产上下文不会公开。

## 仓库结构

- `Sources/PetsGraphCore/`：宠物包校验、动作图、时间轴与 root motion。
- `Sources/PetsGraphApp/`：AppKit 透明窗口、逐帧渲染、菜单和桌面交互。
- `tools/build-prototype-package.py`：把固定 PNG 事实源编译为版本化宠物包。
- `tools/build-cropped-rgba-package.py`：从获批 PNG 包生成固定 clip 裁剪的低功耗运行时副本。
- `tools/build-macos-app.py`：把已校验宠物包嵌入通用 PetsGraph App。
- `tools/build-release-artifacts.py`：原子生成 DMG、App ZIP、校验和与发布元数据。
- `.github/workflows/release.yml`：校验标签、测试、精确附件集合、哈希、Bundle 身份和 arm64 架构，再发布草稿 Release。
- [`AIREADME/CORE.md`](AIREADME/CORE.md)：产品身份、范围和红线。
- [`AIREADME/SPEC.md`](AIREADME/SPEC.md)：宠物包、动作图、场景和交互契约。
- [`AIREADME/DEPLOYMENT.md`](AIREADME/DEPLOYMENT.md)：构建、安装、发布和回滚方式。

## 本地开发

运行 Swift 测试：

```bash
bash tools/test-swift.sh
```

本地生产构建、校验和发布流程见 [`AIREADME/DEPLOYMENT.md`](AIREADME/DEPLOYMENT.md)。素材生成所需的 Seedance 等服务由用户自行配置，凭据不会进入桌面运行时、宠物包或 Release。

## 致谢

感谢朋友制作的 [麻薯 Mochi](https://mochi.xin/)。PetsGraph 立项时参考了它在透明桌面窗口、宠物素材生成和桌面陪伴体验上的探索，并在此基础上选择了安静睡眠陪伴、完整动作图与开源素材包这条更聚焦的方向。

## License

运行时代码使用 [MIT License](LICENSE)。李五百的照片和动画素材可以随官方 Release 用于个人桌面陪伴，其他使用边界见 [ASSETS.md](ASSETS.md)。
