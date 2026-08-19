# Codex 宠物导出

这里维护五百和飞流的 Codex 自定义宠物导出。每个目录都是可以安装到 Codex 的完整 v2 宠物包，包含 `pet.json` 和一张 8 列、11 行的 `spritesheet.webp`。

这两套小型图集是 Codex 桌面宠物资产，不是 PetsGraph App 使用的 `.petsgraph-pet` 连续视频动作包，也不继承 PetsGraph 正式运行时的 `runtime-chain-approved` 状态。两条路线的动作数量、帧结构和人工验收结论彼此独立。

## 当前宠物

| 宠物 | Codex ID | 图集 SHA-256 |
|---|---|---|
| 五百 | `wubai-v0` | `260a092e7bef78ad2005c766ed5c9c0e4cf48195ce4d99c86b5f2839cfbf5624` |
| 飞流 | `feiliu-hatch-native-v1` | `20fc7e6a065bffba85e3d592b3f027fe6e668756790a57b1a61fa3ca7f52177a` |

完整字节数、描述文件哈希和图集尺寸记录在 [`manifest.json`](manifest.json)。

## 校验与安装

在仓库根目录运行：

```bash
python3 tools/manage-codex-pets.py validate
python3 tools/manage-codex-pets.py install
```

默认安装到 `${CODEX_HOME:-~/.codex}/pets/`。只安装一只宠物时传入稳定 ID：

```bash
python3 tools/manage-codex-pets.py install wubai-v0
python3 tools/manage-codex-pets.py install feiliu-hatch-native-v1
```

安装器会先完整校验仓库资产。目标目录内容完全相同时保持不变；同名目录内容不同时默认停止，不覆盖现有宠物。明确要替换时使用 `--force`，旧目录会先移动到 `${CODEX_HOME:-~/.codex}/pets-backups/<时间>/`，不会直接删除。

安装后在 Codex 设置的 Pets 页面重新选择宠物。若设置页仍显示旧图集，重新启动 Codex。

## 维护约定

- 保持每包只有 `pet.json` 和 `spritesheet.webp`，目录名、`pet.json.id` 和 manifest ID 必须一致。
- 已经分发的 ID 不原位改写视觉内容。大幅调整使用新的版本化 ID，并保留旧目录供回滚。
- 更新任一文件后同步更新 `manifest.json` 的字节数和 SHA-256，再运行校验器。
- 机械校验只证明图集结构和完整性。动作连贯性、宠物身份和视觉质量仍需要在真实 Codex 窗口中人工观看。

素材使用边界见仓库根目录的 [`ASSETS.md`](../ASSETS.md)。
