# Pocket Poster / Trash

This adds the older-system wallpaper route from [leminlimez/Pocket-Poster](https://github.com/leminlimez/Pocket-Poster/tree/fb07aa45586ea4d2590c6f6d258777b207e1b8c9). It is separate from the later `worse_query` Pocket Poster forks. This source integration is **not yet compiled or device-validated in Pawster**.

## Enabled policy and evidence

| System | Pocket / Trash | Default |
| --- | --- | --- |
| iOS/iPadOS 17.0–18.7.2 | Experimental | Pocket / Trash |
| iOS/iPadOS 26.0–26.1 | Experimental alternative | `worse_query` |
| iOS 16, 18.7.3+, 26.1.1+, and 27.x | Not enabled for this method | Other engines only where independently supported |

The main repository describes iOS 17–26.1 support. Its [SymHandler](https://github.com/leminlimez/Pocket-Poster/blob/fb07aa45586ea4d2590c6f6d258777b207e1b8c9/Pocket%20Poster/Controllers/SymHandler.swift) selects store 61 from iOS 17 onward. [PosterBoardManager](https://github.com/leminlimez/Pocket-Poster/blob/fb07aa45586ea4d2590c6f6d258777b207e1b8c9/Pocket%20Poster/Controllers/PosterBoardManager.swift) links the app's `.Trash` to a descriptor directory, then calls `FileManager.trashItem` on a local UUID-named copy. It does not grant target read access.

The community publisher's [setup guide](https://github.com/squairdev/pocketposter/blob/63f268df9471c4fbeace6582cf6ad67ed7ec309d/README.md) lists 17–18.7.2 and 26.0–26.2 beta 1. [Issue 55](https://github.com/leminlimez/Pocket-Poster/issues/55) reports a 26.1 success followed by a 26.2 failure; the guide publisher [reports later 18.7 patches as fixed](https://github.com/leminlimez/Pocket-Poster/issues/68). These are upstream/community reports, not Apple guarantees or Pawster device results. Pawster conservatively stops at 18.7.2 and 26.1, without enabling unconfirmed later 18.x backports, 26.2 betas or preliminary iOS 16 support.

The project and Rust framework deployment targets are now **17.0**, and the native syntax-check target follows that minimum. The existing SwiftUI code uses iOS 17-or-earlier APIs; [Apple lists `trashItem` from iOS 11](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)). This source/API audit does not replace compilation, linking or runtime testing on iOS 17. Rebuild the Core Framework before compiling the changed app; do not reuse a framework built with a minimum of iOS 26.

## Setup without mandatory networking

1. Complete the risk notice and installation prerequisites. In the Pocket setup guide, paste this device's **PosterBoard container UUID** or full Application container root, then save. A bare UUID is normalized to `/var/mobile/Containers/Data/Application/<UUID>`.
2. Alternatively import a UTF-8 UUID text file up to 4 KiB, such as `NuggetPosterBoardHash`. The source file is retained. Do not supply the Pawster app UUID, a pairing record or arbitrary JSON.
3. An existing Pocket Poster/Nugget setup can supply that UUID. The current [Nugget helper](https://github.com/leminlimez/Nugget/blob/main/src/devicemanagement/device_manager.py) delivers its helper file to Pocket Poster or LiveContainer, not Pawster; copy its output or import the file yourself. No Nugget restore or reset functionality is incorporated.
4. If you already have valid pairing and a local VPN, Connection offers optional InstallationProxy discovery. Older systems import credentials; native Settings pairing remains gated to iOS 27+. Manual transfer requires **no pairing, VPN or App Group**, and does not start automatic VPN monitoring without separate pairing consent.
5. Select a Collections `.tendies`, preview the plan and explicitly confirm. Manual input proves format only, not container identity or directory existence. A missing/incorrect UUID, uninitialized Collections directory, patched system or unsupported wallpaper can all prevent success. No Reset Collections or language-switch workaround is triggered.

## Transaction and cleanup contract

The shared planner creates fresh UUID targets under store 61 / `com.apple.WallpaperKit.CollectionsPoster` only. The source pack stays unchanged; no upstream wallpaper-ID rewriting, video generation, CarPlay operation, web downloader, URL handler or preference overwrite is imported.

Before any transfer, a private receipt is saved. An exclusive local directory is created in this app's Documents and its inode/device identity recorded before copying. Source and local-copy tree digests must match, including hidden files. The `.Trash` link exists only around the system trash call, not while preparing the next descriptor. Cancellation is cooperative and cannot interrupt a synchronous Foundation operation already executing.

Zero return means the system move request completed; it does **not** prove destination hashes, final names, registration or wallpaper visibility. Receipts use `pocketSending`, `pocketSent` and `pocketPartial`, never `filesVerified`. No automatic NeoSpring, registration rewrite or wallpaper rollback is offered. Manual refresh retains its existing warning and is unverified on newly enabled systems.

Completion, failure, next startup and the History cleanup action attempt to remove only this tool's link and inode-matched local copies. An existing real `.Trash` directory, foreign link, replaced stage or malformed ownership record is not deleted or emptied. Cleanup unlinks the link entry, never recursively follows it into the system container. It does not access or remove installed wallpapers. App termination can leave a temporary link until cleanup; avoid managing this app's files concurrently. A crash between exclusive directory creation and recording ownership can leave an untracked empty local UUID folder; unknown folders are not automatically deleted.

Retry requires the explicit duplicate-risk confirmation already used for unverified transfers. It only releases a local plan restriction, preserves the original receipt and sends/deletes nothing. A new attempt uses new UUIDs and may add duplicates.

## License and validation

The adapter is attributed to the pinned GPL v3 source, with upstream exploit credit to Nathan and DuyKhanhTran. It is treated as GPL-3.0-only rather than assigning an unverified or-later permission. The unchanged license text is retained in [ThirdParty](../ThirdParty/Pocket-Poster-GPL-3.0.txt) and bundled for offline reading. Project-owned code keeps its existing license subject to component-specific terms; see [source notices](../ThirdParty/SOURCES.md).

Added native test cases cover UUID parsing and bounded import, local-setup completion without credentials, engine boundaries/defaults, journal-before-send, hidden assets, source preservation, foreign-trash protection, interrupted cleanup, replaced inodes, cancellation, unsafe targets, retry acknowledgement and exclusion from scoped rollback/refresh. They have not been executed here. Resource, syntax and source-contract checks are separate from native build/test results.

Before release, build and run on the oldest iOS 17 environment plus representative iOS 18/26 devices. Independently inspect actual descriptor contents, visibility, unchanged existing wallpapers/preferences, cancellation, process termination and `.Trash` cleanup. A simulator on a newer runtime does not establish iOS 17 exploit compatibility. Keep failed and untested reports visible; never convert upstream support claims into Pawster acceptance.

## 中文说明

已将源码最低部署版本降为 17.0，并增加独立的 Pocket Poster/Trash 实验路径：17.0–18.7.2 默认使用此方式；26.0–26.1 可手动选择，仍默认 worse_query。18.7.3/.4 未确认，因此未启用；已被报告修复的后续补丁、26.2 和 27.x 不走此方式。这里只扩大源码启用范围，尚未完成喵贴在这些系统上的编译和实机确认。

手动填写 PosterBoard UUID 不需要配对或 VPN；导入 UUID 文本不等于导入配对文件。已有配对与 VPN 可用于可选的系统查询。教程、按钮可用状态和配对授权均按这两条路径分开处理。

只在本 App 的本地副本上调用系统“移到废纸篓”，不改写偏好、不重置集合、不切换系统语言。发送请求完成仍显示目标未校验，不能当成壁纸已安装或可见。临时链接清理只处理有本地记录且归属匹配的对象，已有废纸篓或外来链接不会被清空；进程中断和记录损坏仍可能需要人工检查。完整实机步骤见[验证清单](实机验证步骤.md)。
