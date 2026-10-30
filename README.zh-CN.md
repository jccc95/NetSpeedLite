# NetSpeedLite

[English](README.md)

一款轻量的 macOS 原生状态栏网速工具，实时显示上传和下载速度。没有 Dock 图标，不发起网络请求，只使用 Apple 系统框架。

## 功能

- 状态栏以两行紧凑的等宽字体显示下载和上传速度，并保持左对齐。
- 箭头、速率数值和 `/s` 后缀分别对齐；状态栏宽度按文字需要自动调整。
- 每秒读取一次网络接口累计流量并计算实时速率。
- 点击状态栏项目，可查看当前速率和最近 60 秒折线图。
- 提供“登录时启动”选项；首次运行时默认启用。
- 流量历史仅保存在运行内存中，退出后不保留；应用不会发起网络请求。

当前版本不统计单个应用的流量。这里使用的轻量级网络接口计数器不能可靠提供实时的进程级流量。

## 系统要求

- macOS 13（Ventura）或更高版本
- Xcode Command Line Tools，需包含 `swiftc` 和 `codesign`

无需安装第三方依赖。

## 编译和运行

```sh
git clone https://github.com/<你的账号>/NetSpeedLite.git
cd NetSpeedLite
./build.sh
open build/NetSpeedLite.app
```

构建脚本会使用当前 Mac 的处理器架构。安装到“应用程序”目录：

```sh
ditto build/NetSpeedLite.app /Applications/NetSpeedLite.app
open -a /Applications/NetSpeedLite.app
```

本地构建使用临时签名，未经过 Apple 公证。若要向其他用户分发，可能还需要配置开发者签名和公证，以满足 Gatekeeper 要求。

主要实现位于 `NetSpeedLite.swift`；应用包元数据位于 `Info.plist`。

## 工作原理

NetSpeedLite 每秒通过 `getifaddrs` 读取活跃非回环网络接口的累计字节数，将计数相加，再用相邻采样的差值计算当前速率。折线图只在内存中保留最近 60 次采样。

## 许可证

MIT，详见 [LICENSE](LICENSE)。
