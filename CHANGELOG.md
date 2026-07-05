# 更新日志

这里记录面向玩家的产品更新内容。发布 tag 时，CI 会优先读取与 tag 同名的小节作为 GitHub Release 正文和资产内的 `PRODUCT_CHANGELOG.md`。

## Unreleased

- 新增 GitHub Actions 多平台验证、导出与自动发布流程。
- 新增 macOS、iOS、Android release 构建入口，其中移动与 Apple 平台默认允许失败并保留日志。
- iOS release 默认上传 Xcode 工程包，并在签名资料可用时尝试生成 IPA 资产。
- Release 资产会包含产品更新日志，并保留各平台导出日志便于排查。

## v0.1.0

- 完成 3D 中国麻将核心玩法原型。
- 支持人类玩家与 3 个 AI 对局，包含吃、碰、杠、胡、流局与跨局计分。
- 使用 Godot 4.7 以代码生成 3D 场景、UI 与程序化音效。
