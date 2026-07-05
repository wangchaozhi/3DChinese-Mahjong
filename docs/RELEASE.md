# 发布流程

本项目通过 GitHub Actions 自动发布 tag 构建。

## 触发方式

推送任意 tag 会触发 release 构建：

```bash
git tag v0.1.0
git push origin v0.1.0
```

## 构建平台

- Windows: 必需构建，失败会阻止发布。
- Linux: 必需构建，失败会阻止发布。
- Web: 补充构建，允许失败；失败时不会阻止 Windows/Linux release 产物发布。

每个平台 release 压缩包内都会包含 `PRODUCT_CHANGELOG.md`。GitHub Release 资产区也会单独上传 `PRODUCT_CHANGELOG-<tag>.md` 和各平台 `.log`。

## 更新日志

发布前建议在 [CHANGELOG.md](../CHANGELOG.md) 增加与 tag 同名的小节，例如：

```markdown
## v0.2.0

- 新增某项玩家可见功能。
- 修复某个玩家可感知的问题。
```

如果没有找到同名小节，CI 会根据 git commit subject 自动生成一份基础更新日志。
