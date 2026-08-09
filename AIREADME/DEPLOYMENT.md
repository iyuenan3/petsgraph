# DEPLOYMENT：petsgraph

## 主机 + 环境

⚑ 尚无可安装版本。当前有一个本机 macOS 预览原型，运行时离线，宠物素材生成和私有原型包编译均在用户自行 clone 的项目工作区执行。

当前验证环境：macOS、Xcode 26.6 完整版、Swift 6.3.3、Python 3.12 和 Pillow 12.2.0。当前 `xcode-select` 指向的 CommandLineTools 不包含 `Testing` 或 `XCTest` 模块，裸跑 `swift test` 不是可信基线。测试脚本显式使用 `/Applications/Xcode.app/Contents/Developer`，不修改全局 `xcode-select`；当前 13 项 XCTest 全部通过。

## 怎么起

首个原型使用 Swift Package Manager。公开代码测试：

```bash
bash tools/test-swift.sh
```

私有原型包需要 Pillow，使用隔离环境，不修改 Homebrew 或系统 Python：

```bash
uv venv .venv --python /opt/homebrew/bin/python3.12
uv pip install --python .venv/bin/python -r requirements-prototype.txt
.venv/bin/python tools/build-prototype-package.py \
  --config workspaces/wubai-private/runtime-records/wubai-side-stretched-supine-v0.2-source.json \
  --output workspaces/wubai-private/runtime-builds/wubai-side-stretched-supine-v0.2.0-preview.petsgraph-pet
```

校验私有包但不启动窗口：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift run petsgraph \
  workspaces/wubai-private/runtime-builds/wubai-side-stretched-supine-v0.2.0-preview.petsgraph-pet \
  --validate-only
```

启动透明原生窗口：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift run petsgraph \
  workspaces/wubai-private/runtime-builds/wubai-side-stretched-supine-v0.2.0-preview.petsgraph-pet \
  --display-height 150
```

当前 0.2.0 聚焦预览包包含 15 个片段、7 个节点、8 条边和 1,145 个完整性条目。原型在菜单栏显示爪印，可重新播放当前预览链或退出。该链已录制但仍等待人工运行时结论，它不是正式安装入口。

## 域名 / 入口

无。第一阶段不提供 Web 服务、云端 API 或公网入口。

## 生成服务配置

- 用户自行配置 Seedance 等 provider 的凭据与额度。
- 凭据只能进入本机环境变量、系统钥匙串或被忽略的本地配置，不得写入 AIREADME、Git、日志、预览或宠物包。
- 素材 Skill 在每次产生付费调用前展示动作、模型、尝试序号和预计调用数。
- 网络结果未知时不自动重投；每个动作或过渡的受控尝试总数最多为 3。

## 本地安装入口

⚑ 正式安装目录和应用入口仍待确定。当前私有包只从显式命令行路径预览。正式方案必须满足：

- 本地导入 `.petsgraph-pet`。
- 先严格验证，再原子安装。
- 新包失败时保留当前可用版本。
- 包版本可并存或可回滚，不覆盖历史批准资产。

## 共享底座引用

无。生成 provider 是用户外部配置，不是 petsgraph 托管底座。

## 备份 / 升级 / 回滚

- 原始照片和视频母片属于用户私有制作工作区，由用户自行备份，不默认打包分发。
- 已批准宠物包通过目录级复制备份。
- 升级使用新版本包，运行时 schema 不兼容时拒绝导入。
- 回滚切回上一份通过完整性校验的已安装包。

## 运维约束

- 运行时不得联网生成或上传宠物素材。
- 锁屏和系统睡眠时暂停窗口与动画时钟，恢复后回到稳定姿态。
- 不因 provider 超时、失败或本地网络错误自动重复付费调用。
- 未通过 `runtime-chain-approved` 的包只能进入显式预览模式，不能替换正式宠物。
