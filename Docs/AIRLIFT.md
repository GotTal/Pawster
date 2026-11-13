# AirTraffic / Airlift

AirTraffic is an experimental folder-transfer option alongside the two scoped-access engines. `worse_query` remains the default. A failed operation never silently changes engines or retries a write.

## Compatibility

Enabled for iOS 27.0–27.0.1 and 27.2 beta 1 (`24B5084k`) / beta 2 (`24B5089g`). Other 27.2 builds, 27.1 and iOS 26 are not enabled for this transport. Requires valid pairing for the same device, a local VPN and the official Apple Books app installed and opened once; close Books and pause synchronization during the transfer; no `Pawster.WQ` App Group is required.

This known Tendies range is already covered by `worse_query`. It adds an alternative when App Group access is unavailable, not evidence of additional OS-version support. AirCard's older-system claims list Wallet/passcode features, so no iOS 18–26 wallpaper support is inferred for AirTraffic. The app’s new iOS 17 minimum comes from the separate Pocket / Trash route, not AirTraffic.

Sources reviewed 2026-11-13: [AirCard README](https://github.com/Mak5er/AirCard-iOS/blob/40640c4d827aeab8d798285b57d24fcf6be070d0/README.md), [folder transport](https://github.com/Mak5er/AirCard-iOS/blob/40640c4d827aeab8d798285b57d24fcf6be070d0/rust-core/src/exploit.rs), [Grappa bridge](https://github.com/Mak5er/AirCard-iOS/blob/40640c4d827aeab8d798285b57d24fcf6be070d0/ios-app/GrappaHelper.m). The beta build mapping is corroborated by the developer's [firmware table](https://github.com/Xplo8E/Liter8/blob/main/README.md). These are source claims, not Pawster device acceptance.

## Transfer contract

1. InstallationProxy locates the container; a manual path must match it. Store 61 and the Collections extension are explicit assumptions on the allowed iOS 27 builds, not inspected filesystem metadata.
2. Review a plan with fresh UUID destinations and an experimental-method notice. The native entry point re-queries the container and derives its fixed Collections path. It exposes no arbitrary target, preference, Wallet or reset interface.
3. Save a receipt before transport; check source digests, reject links/special files, preserve hidden assets. Per descriptor limits: 256 MiB source bytes, 20,000 entries and 32 directory levels.
4. Stage through StreamingZip and send through ATC/Grappa. Connection locking and peer override policy are shared with discovery.
5. Zero return code means **sent, target unverified**. Receipts use `airliftSent`, `airliftSending` or `airliftPartial`, never `filesVerified`. Installed hashes, target existence, registration and visibility remain unconfirmed. No automatic NeoSpring, wallpaper rollback or registration preference rewrite is offered. Manual NeoSpring keeps its normal confirmation.

Upstream always replaces PosterBoard's unprotected preferences after folder injection. Pawster omits that step because this transport cannot read and merge the original file. A sent descriptor may therefore need registration/protection changes that this path cannot safely provide, and may not appear in Settings. This is not parity with upstream's complete flashing sequence or a proven working device path.

A prior AirTraffic attempt blocks another plan for that pack until the user explicitly chooses **Allow Another Attempt** and acknowledges possible duplicate wallpapers. This only changes local retry acknowledgement, keeps the original record and sends/deletes nothing. A new plan receives new UUIDs; pending Books recovery still blocks the native sender.

## Books recovery

Before mutation, a private transaction record saves the original `Books/Sync/Books.plist` bytes or absence, temporary manifest and owned staging identifiers. This can include book sync metadata and is covered by the updated consent/privacy notice. Do not publish recovery files.

Completion, failure or cancellation is followed by bounded cleanup using a fresh AFC session. An unchanged original needs no rewrite; a file matching this operation's temporary manifest can be restored. Independent changes block automatic overwrite. Cleanup unlinks the owned link itself and removes only its staging tree; it does not remove installed wallpapers.

App termination can interrupt cleanup. Pending recovery blocks another AirTraffic send. Recovery also checks the recorded container identity and backup checksums; a different container refuses restoration. Operation History offers **Restore Temporary Sync State** for its owned recovery directories. This action uses ordinary AFC and remains available after an OS update disables injection. Recovery completion does not change the unverified wallpaper status. Connection failures, malformed backups or conflicting current state retain evidence for investigation; recovery from every system/storage failure is not guaranteed.

## Verification

This integration has not been committed, pushed, compiled or executed on a device, and no IPA was built. Source/resource checks cannot prove the transport works. Added native test cases cover engine/build limits, hidden assets/link rejection, recovery record validation, receipt-before-send, unverified results, cancellation, partial failure, unsafe targets and rejection by scoped rollback/refresh.

On a supported device, begin with pairing and read-only path discovery. Explicitly choose AirTraffic, review the notice and use a small authorized Collections fixture. Independently inspect target content, visibility, existing wallpapers, unchanged PosterBoard preferences and restored Books state. Test missing Books/Grappa, peer override, disconnect/cancel, app termination/recovery and independently changed Books state. Compare with `worse_query` on the same configuration. Mark untested cases as untested; do not use Reset Collections as a routine test step.

## 中文说明

AirTraffic/Airlift 不依赖 App Group，但仍需要有效配对、本地 VPN 和 Apple Books。它并未扩大已证实的系统版本范围，也不能将 AirCard 的旧系统 Wallet/拨号支持视为壁纸支持。

它无法检查目标目录或回读已安装内容，界面只显示“已发送、目标未校验”。为保留系统原有状态，不移植上游覆盖 PosterBoard 偏好的步骤，因此可能缺少注册/保护调整，发送后不保证可见；不提供壁纸撤回、注册刷新或自动 NeoSpring，可在检查后手动刷新。

Books 同步状态在发送前保存至本机事务目录，结束、失败或取消后尝试恢复；中断后可从记录恢复临时同步状态，不删除壁纸。当前内容出现独立变化时停止覆盖并保留备份。iOS 26 的导入文件指引及 iOS 27 的本机/导入两种配对方式均保持独立判断。

源码仍待 macOS 编译、原生测试和真实设备验证；语法检查或发送返回码不能证明壁纸成功。

For local macOS validation, rebuild the Core Framework before compiling Swift because this change adds FFI functions. Native compilation/tests were not run here. Full offline dependency resolution was unavailable because the configured local registry cache lacks `plist`; manifest metadata inspection alone is not a dependency build check.
