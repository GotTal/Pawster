# Pawster 0.3.1 Test / 测试说明

This patch improves connection setup and status reporting without changing the enabled wallpaper engines or system-version ranges.

- Connection and Getting Started show Wi-Fi path availability independently of the VPN route. A connected VPN alone is not displayed as a connected wireless LAN.
- LocalDevVPN instructions, restart/query-error hints and both READMEs remind users to connect to Wi-Fi and keep it connected during use.
- Wireless observation starts with foreground connection monitoring, stops when status is reset, and ignores callbacks from retired observers. No SSID or location is read and no internet probes are sent.
- Compatibility wording in both READMEs focuses on Pawster's own capabilities; Credits now includes Pocket Poster.

The test channel keeps the app's bundle identifier and replaces an installed release; the two cannot coexist. CI assigns the build number and records the exact source commit in the IPA. This test does not merge main or publish a new formal Release.

Native tests cover independent Wi-Fi/VPN states, observer reuse, reset/restart and late callbacks. CI and simulator checks cannot establish the actual Wi-Fi/VPN combination on every device.

实机重点：分别确认无线局域网与 VPN 的徽章；仅蜂窝网络、关闭无线局域网或拒绝网络权限时，检查连接提醒；测试无线局域网切换、进入后台及返回 App 后状态是否及时更新。LocalDevVPN 使用期间应连接无线局域网。手动 UUID 的本地 Trash 操作仍不强制要求配对或 VPN。

0.3.1 is a patch-level setup/status improvement over 0.3.0; actual wireless path reporting and wallpaper operations still require device validation.
