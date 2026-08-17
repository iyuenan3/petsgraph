# DEPLOYMENT：petsgraph

## 当前发布基线

PetsGraph `0.5.10` 是 Apple 芯片专用双宠正式版，最低支持 macOS 14。App 名称为 `PetsGraph`，Bundle ID 为 `com.maxwell.petsgraph`，使用 ad-hoc 签名，尚未使用 Developer ID 或 Apple 公证。

| 宠物 | 内嵌包 | clip | 帧 | `baseHeightPt` | 状态 |
|---|---|---:|---:|---:|---|
| 五百 | `wubai-quiet-companion-0.5.10` | 53 | 6,866 | 172.5 | `runtime-chain-approved`、`installable=true` |
| 飞流 | `feiliu-quiet-companion-0.5.10` | 31 | 5,147 | 181.125 | `runtime-chain-approved`、`installable=true` |

两包均使用 schema `0.4.0` 与 `cropped-rgba-clips`。飞流在 1.0× 下比五百大 5%。正式 App 为 `dist/PetsGraph-0.5.10.app`，本地 Release 产物为 `workspaces/release-dist/v0.5.10/PetsGraph-v0.5.10-macOS-arm64.dmg`。

DMG 固定属性：

- 字节数：`856000287`
- SHA-256：`460395f97c46899eea13947fa8606fc9271f6a02e1171cb3281d98a37cf2bca6`
- 主可执行架构：严格为 `arm64`
- Release 附件：精确一个 DMG

公开 Release 不提供 App ZIP、预览图、校验和附件或独立 `.petsgraph-pet`。附件哈希记录在 `release/manifests/v0.5.10.json`。

## 用户安装

公开入口：<https://github.com/iyuenan3/petsgraph/releases/tag/v0.5.10>

1. 下载 `PetsGraph-v0.5.10-macOS-arm64.dmg`。
2. 打开 DMG，把 `PetsGraph.app` 拖入“应用程序”。
3. 首次启动如被 macOS 阻止，在 Finder 中右键 App 选择“打开”，或在“系统设置 → 隐私与安全性”中确认。
4. 首次安装默认同时装载五百和飞流，并在屏幕左下角横排。

App 离线运行，不上传照片，不访问生成服务，不收集遥测，也不要求辅助功能权限。

## 本机构建与验证

测试必须使用完整 Xcode 基线：

```bash
bash tools/test-swift.sh
```

构建正式 App：

```bash
python3 tools/build-macos-app.py \
  --package workspaces/wubai-private/runtime/wubai-quiet-companion-0.5.10.petsgraph-pet \
  --package workspaces/feiliu-private/runtime/feiliu-quiet-companion-0.5.10.petsgraph-pet \
  --output dist/PetsGraph-0.5.10.app \
  --version 0.5.10 \
  --min-macos 14.0
```

构建唯一发布附件：

```bash
python3 tools/build-release-artifacts.py \
  --app dist/PetsGraph-0.5.10.app \
  --output workspaces/release-dist/v0.5.10 \
  --version 0.5.10
```

正式构建必须通过：

- 67 项 XCTest。
- 两个包的 schema、版本、批准状态、图、完整性和全部 12,013 帧媒体校验。
- App 主可执行文件 `arm64` 架构检查。
- `codesign --verify --deep --strict`。
- `hdiutil verify`，挂载后再次检查 App、签名、版本和两个内嵌包。
- 发布目录精确只有一个 DMG，字节数和 SHA-256 与仓库清单一致。

DMG 使用本机 `/usr/bin/hdiutil create` 从冻结 App 构建。GitHub Actions 不重新编译媒体或 App，只验证并发布这份已验收附件。本机受限沙箱可能让 `hdiutil` 报“设备未配置”，此时必须确认没有残留半成品，再以明确的磁盘映像权限重跑同一确定性命令。

## GitHub 发布流程

1. 先提交实现并执行测试、包校验、App 校验和 DMG 校验。
2. 以实现提交更新 README、AIREADME、Release 说明和固定清单，单独提交文档。
3. 在文档提交上创建带注释标签 `v0.5.10`，推送 `main` 与标签。
4. 使用 `docs/releases/v0.5.10.md` 创建草稿 Release，只上传清单指定的 DMG。
5. 手动触发 `.github/workflows/release.yml`，输入标签 `v0.5.10`。
6. GitHub Actions 检出精确标签，执行测试、下载并校验草稿附件、挂载 DMG、检查 arm64、签名、版本、双宠包和媒体，再发布草稿。
7. 发布后回读 Release，确认不是草稿、不是预发布、附件数量严格为一、名称、字节数和摘要匹配清单。

任何附件、标签或提交不一致都必须停止发布。不能原位移动已有正式标签，也不能用另一次远端编译替代本机人工验收过的 DMG。

## 回滚与运维

- 历史标签、Release、五百 PNG 基线和飞流制作事实源保留，不覆盖或删除。
- 正式媒体不进入 Git 历史，只保留小型清单、构建器与验证逻辑。
- 重复启动由每用户进程锁在加载大媒体前退出，避免出现两个 PetsGraph 进程。
- App 只使用一个共享 24 Hz 渲染 Timer，每只宠物仍拥有独立行为会话和随机时钟。
- 双宠长期 CPU 与内存继续收集真实数据。性能结论必须注明唯一 PID、测量工具、稳定睡眠或过渡场景，不能把旧 AppTranslocation 进程计入当前版本。
- 下一版如改变素材、位置、体型、窗口命中、动作图或发布附件，必须重跑相应自动检查和真实桌面人工闸门。
