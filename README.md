# NetSpeedLite

[简体中文](README.zh-CN.md)

A tiny native macOS menu bar app for live upload and download speeds. It has no Dock icon, makes no network requests, and uses only Apple system frameworks.

## Features

- Shows download and upload rates in two compact, left-aligned monospaced lines.
- Aligns the arrows, rate values, and `/s` suffix; the menu bar item grows only as needed.
- Samples network interface byte counters once per second.
- Click the menu bar item to see current rates and a rolling 60-second chart.
- Shows the top five active processes by live receive/send rate in the popover, using macOS's built-in `nettop` command.
- Offers a **Launch at Login** checkbox. On first launch, login startup is enabled by default.
- Keeps no traffic history after the app exits and makes no network requests.

The process list is a best-effort breakdown, not a guaranteed app-level accounting report. Browser helpers, VPNs, proxies, and system services may own the network connection, so traffic may appear under those process names rather than the visible app. Per-process rates may not add up exactly to the interface-wide total.

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools, including `swiftc` and `codesign`

No third-party packages are required.

## Build and run

```sh
git clone https://github.com/jccc95/NetSpeedLite.git
cd NetSpeedLite
./build.sh
open build/NetSpeedLite.app
```

The build uses the architecture of the Mac on which it runs. To install it for the current user:

```sh
ditto build/NetSpeedLite.app /Applications/NetSpeedLite.app
open -a /Applications/NetSpeedLite.app
```

The locally built app is ad-hoc signed and is not notarized by Apple. A distributed build may require additional signing and notarization for Gatekeeper.

The main implementation is in `NetSpeedLite.swift`; `Info.plist` contains the app bundle metadata.

## How it works

Every second, NetSpeedLite reads cumulative byte counters for active non-loopback interfaces with `getifaddrs`, sums the counters, and computes the rate from the difference between successive samples. The chart keeps the most recent 60 samples in memory.

For the process list, it reads one-second deltas from macOS `nettop` and shows the five processes with the most combined inbound and outbound traffic. No Network Extension or extra system permission is requested.

## License

MIT. See [LICENSE](LICENSE).
