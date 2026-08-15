# ChatGPT 订阅额度监控

[English](#english) | 中文

一个轻量的 macOS 菜单栏应用，用于查看 ChatGPT 订阅额度，以及本机 Codex 使用记录中的近期用量趋势。

> 非官方项目，与 OpenAI 或 ChatGPT 没有隶属、认可或合作关系。

## 功能

- 在 macOS 菜单栏显示订阅额度的使用进度与重置时间。
- 汇总近 90 天的本机 Codex 用量趋势。
- 每 30 秒刷新一次本机数据。
- 不需要 API Key，也不会发起网络请求。

## 隐私

应用只在本机读取以下目录中的 Codex 会话 JSONL 文件：

- `~/.codex/sessions`
- `~/.codex/archived_sessions`

它从会话事件中提取额度百分比、重置时间和 token 用量字段以生成显示内容。应用不会上传、发送或额外保存会话内容。请在使用前自行确认你接受该本机读取行为。

## 系统要求

- macOS 14 或更高版本
- Apple Silicon Mac（当前构建默认生成 arm64 应用）
- Xcode Command Line Tools（包含 `swiftc`、`iconutil` 和 `codesign`）

安装命令行工具：

```zsh
xcode-select --install
```

## 构建与运行

```zsh
git clone https://github.com/wx61666-a11y/chatgpt-subscription-quota-monitor.git
cd chatgpt-subscription-quota-monitor
./scripts/build.sh
open 'build/ChatGPT 订阅额度监控.app'
```

构建产物会放在 `build/`，并使用 ad-hoc 签名。若 macOS 在首次运行时拦截它，请在“系统设置 → 隐私与安全性”中选择允许打开。

## 许可证

本项目基于 [MIT License](LICENSE) 发布。

## English

A lightweight macOS menu-bar monitor for ChatGPT subscription quota and local Codex usage trends.

### Privacy

The app reads Codex session JSONL files from `~/.codex/sessions` and `~/.codex/archived_sessions` on-device. It extracts quota percentage, reset time, and token-usage fields for display only. It does not require an API key, upload data, make network requests, or persist session content.

This is an unofficial project and is not affiliated with, endorsed by, or sponsored by OpenAI or ChatGPT.
