# LinguaFlow

LinguaFlow 是一组面向 macOS 的本地优先双语输入源：`LinguaFlow 中文` 使用 Rime 生成拼音候选并实时显示英文，`LinguaFlow English` 直接输入英文并实时显示中文和本地拼写建议。

## 当前能力

- macOS 26 原生 InputMethodKit 输入源。
- 全拼、简体中文，以及统一显示拼音、横向候选和英文的紧凑浮层。
- 输入停顿 400ms 后，根据当前高亮候选生成中文到英文的本地预览，无需先确认上屏。
- 独立的 `LinguaFlow English` 输入源直接透传英文按键，停顿后生成中文预览。
- 英文单词输入到 2 个字母后，使用 macOS 本地词典显示最多 5 个补全/纠错候选，并在候选旁异步显示本地生成的简短中文释义。
- 按左右或上下方向键移动候选，按 `Tab` 接受高亮项，按 `1`–`5` 直接选择；按空格则保留自己原样输入的单词。
- 浮层跟随当前插入点，屏幕下方空间不足时自动显示在插入点上方。
- `Control + Return` 在光标处插入当前译文。
- `Shift + Control + Return` 换行插入当前译文。
- 切换应用、移动光标、关闭输入法或进入安全输入时清空翻译上下文。
- 翻译模型和文本均由 Apple Translation framework 在设备本地处理。

## 安装

从 [GitHub Releases](https://github.com/Janglejay/LinguaFlow/releases) 下载适用于 Apple 芯片的 `.pkg`，双击后按安装器提示完成。安装程序会一次安装并尝试启用：

- `LinguaFlow 中文`
- `LinguaFlow English`

安装包已经内嵌 Rime 和全部运行依赖，最终用户不需要安装 Homebrew。系统要求为 macOS 26 或更新版本及 Apple 芯片 Mac。

当前测试包尚未使用 Apple Developer ID 签名和公证。如果 macOS 拦截从 GitHub 下载的安装包，请先尝试打开一次，再前往“系统设置 → 隐私与安全性”选择“仍要打开”。正式签名和公证完成后将不再需要这个额外步骤。

安装完成后可以直接从菜单栏切换两套输入法。两套输入源已由安装器启用，因此 macOS 的“添加输入法”搜索页可能不再重复显示它们；请在“当前已启用的输入源”列表或菜单栏中查找。如果列表没有立即刷新，请先关闭并重新打开系统设置，仍未出现时注销并重新登录。第一次使用翻译前，从输入法菜单选择“准备本地中英翻译…”，在随附的设置助手中允许 Apple 下载中文和英语模型。

完整的安装、迁移和开发者签名说明见 [docs/INSTALL.md](docs/INSTALL.md)。

## 从源码构建

构建机器需要 macOS 26、Swift 工具链、Homebrew 和 `librime`：

```bash
git clone --recurse-submodules https://github.com/Janglejay/LinguaFlow.git
cd LinguaFlow
brew install librime
./scripts/install-local.sh
```

生成可分发安装包：

```bash
./scripts/build-installer.sh release
```

## 开发验证

```bash
swift run linguaflow-core-checks

shared_dir=$(./scripts/prepare-rime-data.sh)
user_data_dir=$(mktemp -d .build/rime-user-check.XXXXXX)
swift run linguaflow-rime-checks "$shared_dir" "$user_data_dir"

swift run linguaflow-translation-checks
./scripts/build-app.sh release
./scripts/build-installer.sh release
# 安装刚生成的 .pkg 后再运行：
./scripts/check-installed-input-sources.swift
```

`linguaflow-translation-checks` 在模型尚未下载时会以退出码 2 返回；这是环境状态，不是构建失败。

标准 XCTest 文件保留在 `Tests/`。当前机器尚未接受完整 Xcode 许可，Command Line Tools 环境缺少 XCTest，因此日常验证暂时使用两个无依赖自检程序。

## 隐私边界

- 输入和翻译热路径不调用第三方网络 API。
- 只记录当前 InputMethodKit 会话中由 LinguaFlow 自己提交的文本，不读取任意宿主文档前文。
- 翻译缓冲上限为 280 个字符。
- 失焦、切换输入源、方向键移动和 Secure Event Input 会取消翻译并丢弃上下文。
- 当前版本不保存翻译历史和原始句子。

## 已知限制

- 当前发布包仅支持 Apple 芯片 Mac；尚未提供 Intel 或 Universal 版本。
- 当前测试安装包没有 Developer ID 签名和 Apple 公证，从 GitHub 下载后会出现 Gatekeeper 提示。
- 候选暂时只支持键盘选择，尚未实现鼠标点击和翻页按钮。
- 翻译快捷键是在光标处追加译文，不会自动替换已经上屏的原文。
- `LinguaFlow English` 当前提供单词补全和拼写纠错；候选来自系统词典，不会根据完整语境预测下一词，更复杂的语法与表达润色不在本版本范围内。
- 尚未完成 Notes、Safari、Chrome、VS Code 等宿主的人工兼容性矩阵。
- Apple 翻译模型需要用户首次明确授权下载。

## 目录

- `Sources/LinguaFlowCore`：句子缓冲、请求修订号和异步结果验旧。
- `Sources/LinguaFlowRimeBridge`：极窄的 C/librime 边界。
- `Sources/LinguaFlowRime`：Swift 拼音引擎封装。
- `Sources/LinguaFlowIME`：InputMethodKit、候选/英文预览浮层。
- `Sources/LinguaFlowSetup`：Apple 本地翻译模型准备助手。
- `Vendor/`：以 Git submodule 引用的 Rime 配置和词典数据。

项目代码采用 MIT License。Rime 组件和输入方案保留各自许可证，详见 `THIRD_PARTY_NOTICES.md`。
