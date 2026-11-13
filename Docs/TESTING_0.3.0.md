# Pawster 0.3.0 Test / 测试说明

0.3.0 is a minor feature update over 0.2.0: it adds two transfer paths, extends the deployment target to iOS 17, changes engine selection/compatibility policy and renews explicit risk consent. Test packaging uses the test channel, a run-specific build number and source revision; this is not a formal release or device acceptance.

新增能力包括 AirTraffic/Airlift 与原版 Pocket Poster/Trash、双/多引擎选择、精确 beta 构建判断、iOS 17 最低部署、临时状态恢复及风险确认。配对状态行和路径按钮也已调整，因此版本由 0.2.0 提升为 0.3.0；测试包保留测试标识，暂不合并 main 或发布正式 Release。

- `worse_query` remains the default where available. Older 17.0–18.7.2 systems use the experimental Pocket route. Source-enabled ranges are documented in [COMPATIBILITY.md](COMPATIBILITY.md), not universally device-verified.
- [AirTraffic](AIRLIFT.md) and [Pocket / Trash](POCKET_POSTER.md) return unverified transfer results. They do not automatically rewrite registration preferences, roll back system wallpapers or trigger automatic NeoSpring. Inspect system results independently.
- Pocket manual UUID mode needs no pairing/VPN; optional discovery uses imported credentials on older systems. AirTraffic still requires pairing, a local VPN and Apple Books on its listed builds.
- Updated risk/privacy consent must be explicitly accepted again. Nothing automatically clears existing wallpapers or resets Collections.
- Test and release builds keep the same bundle identifier. Installing the test build replaces the installed release; they cannot coexist. Older app versions may not display receipts for newly introduced engines. Keep relevant transaction evidence before downgrading.

Windows checks validate language resources, documents, Python tests and source syntax. GitHub Actions supplies native compilation, Rust tests and simulator tests before packaging. Check the exact run/commit for its result. Even a successful build or simulator run cannot establish actual iOS 17/18 service behavior, pairing/PiP cleanup, system wallpaper visibility or device-specific recovery.

首轮实机重点：配对状态空白是否消失；路径按钮是否清楚；现有 worse_query 注入是否回归正常；真实 iOS 17 的安装及 Pocket 临时链接清理；AirTraffic 的 Books 状态恢复；手动/自动刷新提示及系统壁纸可见性。未执行的项目必须记为“未测试”。完整步骤见[实机验证](实机验证步骤.md)。
