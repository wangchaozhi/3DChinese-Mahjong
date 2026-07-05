# 3D 中国麻将

[![Godot CI](https://github.com/wangchaozhi/3DChinese-Mahjong/actions/workflows/godot-ci.yml/badge.svg)](https://github.com/wangchaozhi/3DChinese-Mahjong/actions/workflows/godot-ci.yml)
[![Release](https://img.shields.io/github/v/release/wangchaozhi/3DChinese-Mahjong?label=release)](https://github.com/wangchaozhi/3DChinese-Mahjong/releases)

一款用 Godot 4.7 和 GDScript 编写的完整 3D 中国麻将。项目包含 136 张牌、人类玩家与 3 个 AI、吃碰杠胡、跨局计分、3D 牌桌、代码生成 UI 和程序化音效。

## 特色

- 支持吃、碰、明杠、暗杠、补杠、抢杠胡、自摸、点炮和流局。
- 内置番型与零和计分，支持多局累计分数。
- AI 使用向听数搜索、弃牌价值评估和已见牌信息做决策。
- 3D 场景、牌面、UI、音效全部由代码生成，无外部美术资源依赖。
- GitHub Actions 自动验证并在 tag 时导出 Windows、Linux、Web、macOS、Android、iOS 资产。

## 下载

前往 [Releases](https://github.com/wangchaozhi/3DChinese-Mahjong/releases) 下载最新版本。

Release 资产通常包含：

- Windows x86_64 压缩包
- Linux x86_64 压缩包
- Web 静态包
- macOS universal 压缩包
- Android arm64 APK
- iOS Xcode 工程包；如果仓库配置了 Apple 签名资料，CI 会额外尝试生成 IPA
- `PRODUCT_CHANGELOG-<tag>.md` 产品更新日志和各平台导出日志

## 运行项目

需要 Godot 4.7 stable。建议使用带控制台输出的 Godot 可执行文件，方便查看脚本解析和运行日志。

如果 `godot` 已加入 PATH：

```powershell
godot --path .
```

如果未加入 PATH，请把 `godot` 替换为本机 Godot 4.7 console 可执行文件路径：

```powershell
& "C:\Path\To\Godot_v4.7-stable_win64_console.exe" --path .
```

## 开发验证

刷新导入并检查 GDScript 解析错误：

```powershell
godot --headless --path . --import
```

运行自动对局回归测试。该模式会让 AI 代打人类座位，20 倍速完成 6 局后退出：

```powershell
$env:MJ_AUTOPLAY = "1"
godot --headless --path . --quit-after 200000
Remove-Item Env:\MJ_AUTOPLAY
```

可选的视觉验证会渲染帧序列和音轨：

```powershell
godot --path . --write-movie .\movie\mj.png --quit-after 240
```

退出时若出现少量 `ObjectDB instances leaked`，通常是 Godot quit 阶段 Tween 释放警告，当前项目中可忽略。

## 发布流程

推送 tag 会触发 GitHub Actions 自动构建并创建 GitHub Release：

```powershell
git tag v1.0.0
git push origin v1.0.0
```

Windows 和 Linux 是必需构建，失败会阻止发布。Web、macOS、Android、iOS 是补充构建，允许失败并保留导出日志。详细变量、Secrets 和签名配置见 [docs/RELEASE.md](docs/RELEASE.md)。

## 项目结构

| 路径 | 说明 |
|---|---|
| `scripts/rules.gd` | 胡牌判定、听牌、番型和牌名工具 |
| `scripts/ai.gd` | AI 向听数搜索、出牌和鸣牌决策 |
| `scripts/game.gd` | 游戏状态、异步流程、鸣牌仲裁和计分 |
| `scripts/main.gd` | 3D 场景、UI、输入、音频和视觉布局 |
| `scripts/tile_node.gd` | 单张 3D 牌节点 |
| `scripts/sfx.gd` | 程序化音效合成 |
| `scenes/main.tscn` | 极简主场景，只挂载 `main.gd` |
| `docs/ARCHITECTURE.md` | 详细架构、数据模型和算法说明 |
| `docs/RELEASE.md` | CI 发布、签名和 release 资产说明 |

## 设计约定

本项目刻意保持 `scenes/main.tscn` 只有一个根节点，牌桌、牌、UI 和音效都在 GDScript 中构建。游戏逻辑层不依赖 3D 或 UI；`main.gd` 只负责展示状态、接收输入并调用 `game.submit()`。

当前牌面使用系统字体显示中文。Windows 下会优先使用微软雅黑；导出到其他平台时，如遇中文字体缺失，建议加入自带 CJK 字体并替换字体加载逻辑。

## 许可证

本项目使用 [MIT License](LICENSE) 开源。
