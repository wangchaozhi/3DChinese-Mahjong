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
- Web: 补充构建，允许失败。
- macOS: 补充构建，允许失败；默认使用 Godot 内置 ad-hoc 签名。
- Android: 补充构建，允许失败；默认生成临时自签 keystore，也支持 GitHub secrets 覆盖为稳定签名。
- iOS: 补充构建，允许失败；默认上传 Xcode 工程包，并尝试在有签名资料时生成 IPA。

每个平台 release 压缩包内都会包含 `PRODUCT_CHANGELOG.md`。GitHub Release 资产区也会单独上传 `PRODUCT_CHANGELOG-<tag>.md` 和各平台 `.log`。

## GitHub 变量与 Secrets

这些值可以在仓库 Settings -> Secrets and variables -> Actions 中配置。未配置时 CI 会使用默认值或跳过对应签名能力。

Variables:

- `ANDROID_PACKAGE_NAME`: Android 包名，默认 `com.wangchaozhi.threedchinesemahjong`。
- `MACOS_BUNDLE_ID`: macOS bundle id。
- `MACOS_CODESIGN_MODE`: macOS 签名模式，默认 `1` 表示 Godot 内置 ad-hoc。
- `IOS_BUNDLE_ID`: iOS bundle id。
- `APPLE_TEAM_ID`: Apple Team ID；iOS 导出工程需要 10 位 Team ID，未配置时使用占位值。
- `IOS_BUILD_IPA`: 是否尝试生成 IPA，默认 `true`。
- `IOS_EXPORT_METHOD_RELEASE`: iOS release export method，默认 `2` 表示 Ad-Hoc。
- `IOS_PROFILE_UUID_RELEASE` / `IOS_PROFILE_SPECIFIER_RELEASE`: iOS provisioning profile 标识。

Secrets:

- `ANDROID_KEYSTORE_BASE64`: Android release keystore 的 base64 内容。
- `ANDROID_KEYSTORE_ALIAS`: Android keystore alias。
- `ANDROID_KEYSTORE_PASSWORD`: Android keystore 密码。
- `APPLE_CERTIFICATE_BASE64`: Apple `.p12` 证书 base64 内容，用于 IPA 签名。
- `APPLE_CERTIFICATE_PASSWORD`: Apple `.p12` 证书密码。
- `IOS_PROVISIONING_PROFILE_BASE64`: iOS `.mobileprovision` 文件 base64 内容。
- `APPLE_TEAM_ID`、`IOS_PROFILE_UUID_RELEASE`、`IOS_PROFILE_SPECIFIER_RELEASE` 也可放在 secrets 中。

Godot 4.7 的 iOS 模拟器只支持 Compatibility renderer；本项目当前使用 Mobile renderer，因此 CI 默认不生成模拟器包。

## 更新日志

发布前建议在 [CHANGELOG.md](../CHANGELOG.md) 增加与 tag 同名的小节，例如：

```markdown
## v0.2.0

- 新增某项玩家可见功能。
- 修复某个玩家可感知的问题。
```

如果没有找到同名小节，CI 会根据 git commit subject 自动生成一份基础更新日志。
