# LinguaFlow 安装包

## 最终用户安装

双击 `LinguaFlow-<版本>-macOS-arm64.pkg`，按 macOS 安装器提示完成安装。安装包会将以下两套输入法一次安装到 `/Library/Input Methods`：

- `LinguaFlow 中文`
- `LinguaFlow English`

两套应用均已内嵌 Rime 及其运行时依赖；中文输入法还随包携带其简体、香港与台湾字形转换所需的 OpenCC 配置和字典。最终用户不需要安装 Homebrew、librime 或 OpenCC。

安装包会把两套输入法固定到上述系统目录，并在构建时拒绝任何可重定位的输入法 Bundle。这样即使机器上曾安装过用户目录版本，macOS Installer 也不会把新文件静默重定位回旧路径。

安装脚本使用公开的 Text Input Source API 为当前桌面用户注册并启用两套输入法，不直接改写 macOS 的偏好设置数据库。如果发现早期版本留在 `~/Library/Input Methods` 的同标识输入法，安装器会在新版落盘后注销并迁移精确匹配的旧 `.app`，同时改用 `.app.disabled` 后缀，避免用户域旧版或备份继续被 LaunchServices 当作输入法发现；不会删除其他输入法。旧副本会移到 `~/Library/Application Support/LinguaFlow/Input Method Backups/`。如果 0.2.0 曾错误地留下 `root` 所有的用户目录副本，安装器会额外验证固定路径、非符号链接、版本、构建号、可执行文件和 Bundle ID，只改变该 Bundle 顶层目录的所有权，不递归修改内容，再以当前登录用户身份完成迁移。0.2.0 创建的旧备份也会按相同规则注销并禁用。

安装器只迁移当前登录账户中的早期副本；同一台 Mac 的其他账户如果曾安装开发版，需要登录对应账户后再次运行安装器，或手动移走该账户 `~/Library/Input Methods/` 下的旧副本。

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
