# LinguaFlow

LinguaFlow 是一个面向 macOS 的本地优先中文输入法原型：使用 Rime 生成拼音候选，在当前输入会话中累计由输入法自己提交的中文，并用 Apple Translation framework 显示自然英文预览。

## 当前能力

- macOS 26 原生 InputMethodKit 输入源。
- 全拼、简体中文，以及统一显示拼音、横向候选和英文的紧凑浮层。
- 输入停顿 400ms 后，根据当前高亮候选生成中文到英文的本地预览，无需先确认上屏。
- 浮层跟随当前插入点，屏幕下方空间不足时自动显示在插入点上方。
- `Control + Return` 在光标处插入英文。
- `Shift + Control + Return` 换行插入英文。
- 切换应用、移动光标、关闭输入法或进入安全输入时清空翻译上下文。
- 翻译模型和文本均由 Apple Translation framework 在设备本地处理。

## 本机安装

前置条件：

- macOS 26 或更新版本。
- Homebrew。
- `librime`。安装脚本会检查它是否已经存在。

构建并安装：

```bash
brew install librime
./scripts/install-local.sh
```

然后前往“系统设置 → 键盘 → 文本输入 → 编辑”，添加“LinguaFlow 英语输入”。macOS 有时需要注销并重新登录，才会刷新输入源列表。

第一次翻译前，从输入法菜单选择“准备本地中英翻译…”，在随附的设置助手中允许 Apple 下载中文和英语模型。

## 开发验证

```bash
swift run linguaflow-core-checks

shared_dir=$(./scripts/prepare-rime-data.sh)
user_data_dir=$(mktemp -d .build/rime-user-check.XXXXXX)
swift run linguaflow-rime-checks "$shared_dir" "$user_data_dir"

swift run linguaflow-translation-checks
./scripts/build-app.sh release
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

- 当前是本机原型，使用 Homebrew 的动态 `librime`，还没有制作可分发的独立安装包。
- 候选暂时只支持键盘选择，尚未实现鼠标点击和翻页按钮。
- 英文快捷键是在光标处追加译文，不会自动替换已经上屏的中文。
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
