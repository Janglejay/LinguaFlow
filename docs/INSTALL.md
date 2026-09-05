# LinguaFlow 安装包

## 最终用户安装

双击 `LinguaFlow-<版本>-macOS-arm64.pkg`，按 macOS 安装器提示完成安装。安装包会将以下两套输入法一次安装到 `/Library/Input Methods`：

- `LinguaFlow 中文`
- `LinguaFlow English`

两套应用均已内嵌 Rime 及其运行时依赖。最终用户不需要安装 Homebrew 或 librime。

安装脚本使用公开的 Text Input Source API 为当前桌面用户注册并启用两套输入法，不直接改写 macOS 的偏好设置数据库。如果发现早期版本留在 `~/Library/Input Methods` 的同标识输入法，安装器只会把精确匹配的两个旧 `.app` 移到 `~/Library/Application Support/LinguaFlow/Legacy Input Methods Backup/`，避免用户域旧版遮蔽新版；不会删除其他输入法。需要时可从该目录恢复。

如果系统的输入源缓存没有立即刷新，请注销并重新登录；也可前往“系统设置 → 键盘 → 文本输入 → 编辑”手动添加。其他 macOS 用户首次使用时也需要在自己的账户中添加输入源。

第一次使用翻译前，从 LinguaFlow 输入法菜单选择“准备本地中英翻译…”，按提示允许 Apple 下载设备端中英翻译模型。

当前构建要求 macOS 26 或更新版本，并面向 Apple 芯片 Mac。

## 开发者构建

构建机器仍需要 Swift 工具链和 Homebrew `librime`，因为它是链接输入；生成的安装包自身不依赖 Homebrew：

```bash
brew install librime
./scripts/build-installer.sh release
```

产物写入 `.build/dist/`。

无证书时会生成适合本机测试的未签名 `.pkg`，应用包采用 ad-hoc 签名。用于 GitHub Release 等公开下载时，需要 Apple Developer Program 的 `Developer ID Application` 与 `Developer ID Installer` 证书，并完成公证：

```bash
CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)' \
INSTALLER_SIGN_IDENTITY='Developer ID Installer: Example (TEAMID)' \
NOTARYTOOL_PROFILE='linguaflow-notary' \
./scripts/build-installer.sh release
```

`NOTARYTOOL_PROFILE` 应提前使用 `xcrun notarytool store-credentials` 写入钥匙串。脚本会等待公证完成，然后 staple 并验证票据。

未签名、未公证的安装包从互联网下载后会触发 Gatekeeper 警告，不应作为面向公众的正式发行版本。
