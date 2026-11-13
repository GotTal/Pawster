# Pawster 0.3.0

## Changes / 本次更新

- Adds experimental Pocket Poster / Trash and AirTraffic / Airlift transfer paths, while keeping `worse_query` as the default where supported. Deployment now starts at iOS 17; enabled engine ranges and exact beta builds are listed in [Compatibility](COMPATIBILITY.md).
- Supports manual engine selection on overlapping versions and separates native pairing availability from wallpaper-engine compatibility. Pocket manual UUID setup does not require pairing or a VPN.
- Adds explicit first-use risk acknowledgement, red warning points and free-use information, with updated English and Chinese terms/privacy explanations.
- Records wallpaper package names in new operation receipts, preserves them after local package deletion, and shows per-package progress, expandable target details and named rollback confirmation. Older records resolve a matching local package when possible.
- Refines pairing status/path controls, fixes display-readiness API availability for iOS 17, and adds a compact XK STUDIO logo link at the bottom of Settings without domain text.

新增旧系统 Pocket / Trash 与 AirTraffic / Airlift 实验性路径，调整引擎选择、兼容性和配对指引；加入首次使用风险确认及免费提示。操作记录现在保存壁纸名称，并列出各包状态和撤回内容。设置底部展示缩小后的 XK STUDIO Logo，点击可访问主页，不再显示域名文字。

## Build and integrity / 构建与完整性

The release IPA is built from the merged `main` commit using the release channel. The tag, explicit source archive and `release.json` identify that same source commit. The actual build number, workflow run and package hash are recorded in `release.json`; no test IPA is relabeled as a release.

The previous test build [0.3.0-test.21](https://github.com/GotTal/Pawster/actions/runs/43392565632) passed 135 Swift tests and 15 Rust tests. The final revision is checked again before publication. The release uses the existing pinned Ed25519 signing identity and includes IPA/manifest detached signatures, checksums and public verification materials. See [verification instructions](VERIFYING_RELEASES.md).

正式包从合并后的 main 使用 release 通道重新构建，不复用测试 IPA。tag、附带源码归档及 release.json 对应同一提交；验签使用既有公钥证书，私钥留在发布者本机，不进入 Actions 或发行附件。

## Validation limits / 验证范围

- Automated checks and simulator tests do not establish physical-device compatibility, successful installation or wallpaper visibility. Current-device pairing/PiP, injection, registration, rollback and NeoSpring still need the [device checklist](实机验证步骤.md).
- Pocket / Trash and AirTraffic report unverified target results. They do not provide automatic wallpaper rollback, registration preference rewriting or automatic NeoSpring. AirTraffic requires Apple Books and has separate synchronization recovery.
- The iOS 17 deployment target does not mean all later OS versions are supported. Older-device transport and cleanup need real iOS 17/18/26 validation. Existing wallpapers must not be reset as a routine workaround.
- Component-specific licensing and outstanding permission checks remain documented in [ThirdParty/SOURCES.md](../ThirdParty/SOURCES.md); a project-wide license does not replace those terms.

自动化通过不等于实机验收。新增发送路径仍为实验性功能，发送结束不代表壁纸已写入或可见；请按兼容性表和实机清单核查。旧系统传输、临时状态恢复和系统界面行为仍有待真实设备确认。

Install with SideStore after verifying the original download. Test/release builds share the same bundle identifier and replace each other; they cannot coexist.
