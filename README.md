<img width="568" height="755" alt="iShot_2026-08-27_17 37 47" src="https://github.com/user-attachments/assets/01ddbb62-15cd-4970-acf0-8fc7ce6c239c" />
<img width="566" height="732" alt="iShot_2026-08-27_17 42 51" src="https://github.com/user-attachments/assets/10b1f560-c365-48e0-af3c-3b8495ea85ff" />
<img width="532" height="735" alt="iShot_2026-08-27_17 43 01" src="https://github.com/user-attachments/assets/468271ca-f309-4c74-b231-2acd52915f11" />
# ChatGPT Subscription Quota Monitor V3

> 一个面向 **macOS + Windows** 的本机 ChatGPT / Codex 订阅额度监控工具。
> 实时读取本机 Codex 会话记录，显示 **周额度、5 小时额度、近 90 天本机用量**，所有数据均在本机处理。

[English](#english) | 中文

---

## V3 双平台版

V3 已将 macOS 与 Windows 统一为 Electron 桌面应用。

### macOS

* 菜单栏显示双圆环额度状态
* 点击菜单栏图标打开完整监控面板
* 支持 Apple Silicon Mac
* 提供 DMG 安装包

### Windows

* Windows 任务栏通知区显示双圆环
* 点击通知区图标打开完整监控面板
* 支持 Windows x64
* 提供 Setup.exe 安装包

---

## 主要功能

### 周额度监控

显示当前 Codex 周期额度的已使用比例，并同步显示额度重置时间。

如果本机 Codex 记录中没有可识别的额度事件，应用会显示 `—`，不会猜测或生成不存在的额度数据。

### 5 小时额度监控

独立显示当前 5 小时额度窗口：

* 已使用比例
* 剩余额度
* 重置时间

可以单独控制是否在状态栏 / 通知区显示。

### 双圆环状态栏

macOS 菜单栏和 Windows 通知区统一采用双圆环显示：

* 周额度
* 5 小时额度

无需打开主界面即可快速查看当前额度状态。

### 近 90 天本机用量

应用会读取本机 Codex 会话记录并生成近 90 天用量视图。

用于查看：

* 每日 Codex 使用情况
* 长期使用趋势
* 活跃日期
* Token 使用规模

所有统计均来自当前电脑中的本机 Codex 数据。

### 三套界面皮肤

V3 内置三套视觉主题：

* 极光棱镜
* 落日玻璃
* 蛋白石光谱

可以在应用面板中随时切换。

### 状态栏显示开关

可以分别控制：

* 周额度
* 5 小时额度
* 状态文字

配置保存在本机。

---

## 数据来源

应用仅读取当前用户电脑中的 Codex 本机记录：

```text
~/.codex/sessions
~/.codex/archived_sessions
```

Windows 下对应当前用户目录中的：

```text
%USERPROFILE%\.codex\sessions
%USERPROFILE%\.codex\archived_sessions
```

应用会从本机 JSONL 记录中提取与显示有关的信息，例如：

* 额度使用比例
* 额度窗口长度
* 额度重置时间
* 事件时间
* Token 使用数据

---

## 隐私

本项目采用 **On-device 本机数据模型**。

应用：

* 不需要 OpenAI API Key
* 不需要登录 ChatGPT 网页
* 不读取浏览器 Cookie
* 不修改 Codex 会话文件
* 不上传 Codex 会话内容
* 不上传 Prompt
* 不上传聊天记录
* 不将本机统计发送到服务器

所有额度解析与 90 天用量统计均在当前电脑本地完成。

---

## 下载

推荐始终下载安装最新版：

https://github.com/wx61666-a11y/chatgpt-subscription-quota-monitor/releases/latest

### Windows

下载：

```text
ChatGPT Subscription Quota Monitor Setup x.x.x.exe
```

运行安装程序即可。

### macOS

下载：

```text
ChatGPT Subscription Quota Monitor-x.x.x-arm64.dmg
```

打开 DMG 后安装应用。

---

## 使用 Codex 自动安装

如果电脑已经安装 Codex，可以直接把下面的地址交给 Codex：

```text
https://github.com/wx61666-a11y/chatgpt-subscription-quota-monitor/releases/latest
```

然后告诉 Codex：

```text
请帮我安装这个 GitHub Release 中最新版本的
ChatGPT Subscription Quota Monitor：

https://github.com/wx61666-a11y/chatgpt-subscription-quota-monitor/releases/latest

请自动判断当前电脑是 Windows 还是 macOS，
下载对应安装包并完成安装。

Windows 使用 Setup.exe。
macOS 使用 DMG。

不要修改项目源码。
如果系统因为应用未签名而阻止启动，
请告诉我需要执行的系统确认操作。

安装完成后启动应用并检查是否正常运行。
```

---

## 从源码运行

需要：

* Node.js
* npm

克隆项目：

```bash
git clone https://github.com/wx61666-a11y/chatgpt-subscription-quota-monitor.git
cd chatgpt-subscription-quota-monitor
```

安装依赖：

```bash
npm install
```

启动开发版：

```bash
npm start
```

---

## 本地构建

### macOS

```bash
npm install
npm run dist:mac
```

生成：

```text
dist/*.dmg
```

当前 GitHub Actions 默认构建 Apple Silicon macOS 版本。

### Windows

```bash
npm install
npm run dist:win
```

生成：

```text
dist/*Setup*.exe
```

当前默认生成 Windows x64 NSIS 安装程序。

---

## GitHub Actions

仓库已经配置 GitHub Actions 双平台自动构建。

每次代码推送后会分别启动：

```text
macOS runner
└── Build DMG

Windows runner
└── Build Setup.exe
```

日常构建只保留最终安装文件：

```text
macOS
└── .dmg

Windows
└── Setup.exe
```

不再上传：

* macOS ZIP
* Windows Portable
* unpacked 临时目录
* blockmap 等中间构建文件

---

## Release

正式版本通过 GitHub Releases 发布。

最新版固定地址：

```text
https://github.com/wx61666-a11y/chatgpt-subscription-quota-monitor/releases/latest
```

因此无论以后发布 V3.0.1、V3.1.0 或更高版本，都可以继续使用同一个地址获取最新版。

---

## 关于代码签名

当前社区构建版本可能没有商业代码签名证书。

因此首次运行时系统可能出现安全提示。

### Windows

Windows SmartScreen 可能提示未知发布者。

确认文件来自本项目官方 GitHub Release 后，可以根据 Windows 提示继续运行。

### macOS

macOS Gatekeeper 可能阻止首次打开未签名应用。

可以进入：

```text
系统设置
→ 隐私与安全性
```

找到被阻止的应用并选择允许打开。

正式公开分发时，可以进一步加入：

* Apple Developer ID
* macOS Notarization
* Windows Code Signing Certificate

---

## 当前版本

```text
V3.0.0
```

V3 主要变化：

* macOS + Windows 统一 Electron 源码
* macOS 菜单栏双圆环
* Windows 通知区双圆环
* 点击状态图标打开完整面板
* 周额度监控
* 5 小时额度监控
* 近 90 天本机用量
* 三套 UI 皮肤
* 状态栏显示开关
* GitHub Actions 双平台自动构建
* 本机隐私数据模型

---

## 项目定位

这个项目是一个：

**本机 Codex 使用记录查看器 + 额度监控桌面工具。**

它不是：

* OpenAI 官方客户端
* ChatGPT 官方额度 API
* OpenAI 账单系统
* ChatGPT 全平台使用量统计器

实际可显示的数据取决于当前电脑中已有的 Codex 本机记录。

如果本机记录不存在、记录格式变化或者近期没有相关额度事件，部分数据可能显示为空。

---

## Disclaimer

本项目为非官方开源项目。

与 OpenAI、ChatGPT 或 Codex 没有隶属、授权、认可、合作或赞助关系。

ChatGPT、OpenAI、Codex 等名称及相关商标归其各自权利人所有。

---

## License

本项目基于 MIT License 发布。

详见：

```text
LICENSE
```

---

# English

## ChatGPT Subscription Quota Monitor V3

A cross-platform local ChatGPT / Codex subscription quota monitor for **macOS and Windows**.

V3 provides:

* Weekly quota monitoring
* 5-hour quota monitoring
* Dual-ring menu bar / system tray status
* 90-day local Codex usage visualization
* Three interface themes
* Independent status display toggles
* Local-only data processing
* Automatic macOS and Windows builds via GitHub Actions

---

## Platforms

### macOS

* Menu bar dual-ring quota indicator
* Click the menu bar item to open the full dashboard
* Apple Silicon support
* DMG installer

### Windows

* Dual-ring system tray indicator
* Click the tray icon to open the full dashboard
* Windows x64 support
* Setup.exe installer

---

## Privacy

The application only reads local Codex records from:

```text
~/.codex/sessions
~/.codex/archived_sessions
```

On Windows:

```text
%USERPROFILE%\.codex\sessions
%USERPROFILE%\.codex\archived_sessions
```

The application does not:

* Require an OpenAI API key
* Sign in to the ChatGPT website
* Read browser cookies
* Modify Codex session files
* Upload prompts
* Upload conversations
* Upload Codex session content

Quota parsing and usage statistics are processed locally on the device.

---

## Download

Always download the latest release from:

https://github.com/wx61666-a11y/chatgpt-subscription-quota-monitor/releases/latest

### Windows

Download the latest:

```text
ChatGPT Subscription Quota Monitor Setup x.x.x.exe
```

### macOS

Download the latest:

```text
ChatGPT Subscription Quota Monitor-x.x.x-arm64.dmg
```

---

## Build from source

```bash
git clone https://github.com/wx61666-a11y/chatgpt-subscription-quota-monitor.git
cd chatgpt-subscription-quota-monitor
npm install
npm start
```

Build macOS DMG:

```bash
npm run dist:mac
```

Build Windows installer:

```bash
npm run dist:win
```

---

## Disclaimer

This is an unofficial open-source project.

It is not affiliated with, endorsed by, sponsored by, or officially connected with OpenAI, ChatGPT, or Codex.

All trademarks belong to their respective owners.

---

## License

MIT License.
