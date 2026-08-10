# petsgraph

petsgraph 是一个面向真实宠物的开源 macOS 桌面陪伴项目。第一款产品是「李五百睡觉陪伴 MVP」：五百大部分时间安静地睡在桌面上，偶尔自然更换睡姿；用户点击它时，它会醒来坐好，再次点击后回去睡觉。

这个项目当前优先解决一件事：让桌面上的它看起来、动起来都像用户真正认识的那只宠物，并且值得长时间安静地陪在身边。

## 首个 MVP

- 默认状态是睡觉，随机时间自然切换已批准睡姿。
- 打开后默认出现在物理屏幕左下角，不遮挡主要工作区。
- 普通地面睡姿和带枕头的睡姿都是核心体验。
- 点击睡眠中的宠物后，沿动作图醒来到正面坐姿。
- 点击坐着的宠物后，沿动作图回到当前场景的睡姿。
- 用户可以把宠物拖到桌面的任意位置，宠物窗口始终位于普通窗口和 Dock 前方。
- 睡姿切换遵守安全退出、目标预加载和完整有向过渡，不随机硬切视频。
- 运行时离线，不上传宠物照片，不连接生成服务。

首个 MVP 不开放点击桌面目的地后走路或跑步，也不自主在桌面巡游。已经制作和验证的走路、跑步与 root motion 素材继续保留，作为后续可选活动能力，不进入安静陪伴的默认行为。

## 为什么使用动作图

每个稳定姿态是节点，每个循环动作和有向过渡是边。例如：

```text
趴卧循环
  → 侧躺蜷睡
  → 侧身伸展
  → 仰卧
  → 返回趴卧
```

带枕头的睡眠属于独立场景。枕头只通过批准的进出场动作出现或离开，并在枕头场景内保持位置、尺度和接触关系连续。靠枕姿势只承担场景网关职责，不作为随机睡姿反复抽取。

## 当前状态

- 李五百睡觉陪伴 `0.2.0` 已完成本地 MVP 验收，状态为 `runtime-chain-approved` 和 `installable=true`。
- 正式包包含 53 个逐帧 clip、14 个姿态节点和 39 条有向边，覆盖 7 种普通睡姿、3 种枕头睡姿和两个场景坐姿。
- 普通与枕头睡眠、点击醒来与返回、随机换姿、安全退出、预加载、全桌面拖动、Dock 前方层级、Space 和锁屏恢复均已完成真实桌面验收。
- 完整 Xcode 下 41 项 XCTest 全部通过；正式包另行通过 6,925 条完整性记录、hidden 标记和内嵌包一致性校验。
- 当前可双击 App 使用本机 ad-hoc 签名，尚未完成 Apple 公证，也没有公开发布二进制和五百的私有素材包。
- 现有走跑与点击目的地移动属于工程验证能力，不是首个 MVP 的产品范围。

真实宠物照片、Seedance 任务记录、未批准候选和私有素材包位于被 Git 忽略的本地工作区，不随公开仓库分发。

## 仓库结构

- `Sources/PetsGraphCore/`：宠物包校验、动作图、时间轴与 root motion
- `Sources/PetsGraphApp/`：AppKit 透明窗口、逐帧渲染和桌面交互
- `tools/build-prototype-package.py`：把固定的 PNG 事实源编译为版本化本地宠物包
- `tools/build-macos-app.py`：把已校验宠物包嵌入本机版本化 macOS App
- `Tests/PetsGraphCoreTests/`：包完整性、动作图、安全退出、预加载与行为规划测试
- `Tests/PetsGraphAppTests/`：点击状态机、默认行为和左下角启动测试
- [`AIREADME/CORE.md`](AIREADME/CORE.md)：产品身份、范围和不可违反的红线
- [`AIREADME/PRD.md`](AIREADME/PRD.md)：睡觉陪伴 MVP 的产品需求和验收标准
- [`AIREADME/SPEC.md`](AIREADME/SPEC.md)：宠物包、动作图、场景和交互数据契约
- [`AIREADME/ARCHITECTURE.md`](AIREADME/ARCHITECTURE.md)：目标架构、当前实现和差距
- [`AIREADME/ROADMAP.md`](AIREADME/ROADMAP.md)：从当前原型到首个可安装 MVP 的路线

## 本地开发

运行 Swift 测试：

```bash
bash tools/test-swift.sh
```

当前私有素材包的构建、校验和运行方式见 [`AIREADME/DEPLOYMENT.md`](AIREADME/DEPLOYMENT.md)。素材生成所需的 Seedance 等 provider 由用户自行配置，凭据不会进入桌面运行时或宠物素材包。

五百的照片、生成母片、任务账本、批准配方、正式素材包和本机 App 均保存在被 Git 忽略的私有工作区。公开仓库只提供运行时代码、数据契约、测试和脱敏生产工具。

## License

[MIT](LICENSE)
