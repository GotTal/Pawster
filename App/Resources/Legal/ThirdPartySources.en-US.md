# Third-party Sources and Modifications

AirCard-iOS: https://github.com/Mak5er/AirCard-iOS, commit 40640c4d827aeab8d798285b57d24fcf6be070d0. Used for pairing, RSD/Lockdown connections, InstallationProxy queries, NeoSpring documents, and vendored idevice / idevice-ffi.

worse_query: https://github.com/forcequitOS/worse_query, commit d1540e20cd82b974d891e0551ced6d6aeb570ac2. Native authorization for the newer engine, GPL-3.0-or-later.

bad_query: https://github.com/forcequitOS/bad_query, commit 73ef6da1adabef0982fd00e36cb85f21b8f8194a. Native authorization for the older engine. The snapshot has no standalone LICENSE; verify permission before public redistribution.

Erosion: https://github.com/jailbreakdotparty/Erosion, commit 585a24a973d1ffa33bb71e48eab59a79cca505e1. Debugging and design reference; its interface and wallpaper handling code were not copied.

AirCard’s MIT notice is retained in AirCard-MIT.txt. idevice declares MIT in Cargo.toml. Its code is from the AirCard vendor snapshot, including OPACK and connection compatibility changes, rather than an unmodified upstream 7bd551c source tree. The idevice-ffi snapshot has no independent license declaration; verify the authorization chain separately.

## Pawster modifications

Adapted AirTraffic folder transfer and ATC/Grappa helpers from the same pinned AirCard snapshot. Restricted destinations to new Collections descriptor UUIDs; added bounded cancellation, persistent Books-state recovery, source-link rejection and explicit unverified transfer states. No generic file-write interface or upstream preference overwrite is exposed.

Added independent operation IDs, cancellation flags, and asynchronous timeouts for pairing and queries. PINs are not intentionally logged.

Changed idevice-ffi to depend on local ../idevice; selected ring and disabled its default aws-lc feature.

Added worse_query release calls on failure paths and identifier lifetime handling for C/Objective-C. The authorization mechanism was not changed.

Added stdint.h to make bad_query.h self-contained. Normalized native C/Objective-C line endings and removed trailing whitespace without changing the mechanism.

Adapted NeoSpring HTML from ios-app/RespringHelper.swift in the same AirCard commit, retaining mechanism credits to @neonmodder123 and @skadz108. Added a single session, persistent option, cancellation, timeout, and background cleanup. Automatic execution follows successful injection and a cancellation check. SwiftUI updates do not repeatedly load the document.

AirCard also cites rooootdev/neospring. No standalone license was found in that repository during this review. This remains an authorization verification item; not all upstream permissions are considered cleared.

ZIP and transaction handling were implemented for Pawster. Cargo.lock pins registry dependencies. The GPL text is in the repository LICENSE. This list does not supply missing licenses for upstream code.

Release review, 2026-11-13: the upstream idevice root LICENSE.txt (Copyright 2026 Jackson Coxson, MIT) is additionally retained as ThirdParty/idevice-MIT.txt and in offline app resources. Source: https://github.com/jkcoxson/idevice/blob/master/LICENSE.txt. This supplies the text for idevice's existing MIT declaration; it does not establish that the current upstream tree matches the AirCard vendor snapshot. The idevice-ffi snapshot's authorization chain, bad_query, and the further NeoSpring source remain verification items.

Local VPN inspection references NetworkStatus.swift from the same AirCard snapshot, retaining its MIT notice. Interface and UDP route-source inspection send no probe packets. Pawster checks the active tunnel route for the selected peer instead of treating any utun as service readiness. A peer override disables default peer fallbacks.

AirTraffic/Airlift additionally adapts rust-core/src/exploit.rs (folder transport and protocol helpers), grappa.rs and ios-app/GrappaHelper.[hm] from the same AirCard source pin under its retained MIT notice. Destinations are limited to new Collections descriptor UUIDs, with source validation, cancellation/timeouts, Books sync backup/recovery and explicit unverified results. Generic writes and preference replacement are not exposed.

## Pocket Poster / Trash

Source: https://github.com/leminlimez/Pocket-Poster, pinned commit fb07aa45586ea4d2590c6f6d258777b207e1b8c9. Adapted the Collections .Trash-link and FileManager.trashItem flow from SymHandler.swift and PosterBoardManager.swift, created by lemin in 2025. Upstream credits Nathan (verygenericname) and DuyKhanhTran (khanhduytran0) for the exploit. The adapter retains GPL-3.0-only treatment and the unmodified upstream GPL v3 text in Pocket-Poster-GPL-3.0.txt; it is not relabeled as MIT or automatically granted an or-later permission. Project-owned code retains its existing license, subject to each component’s terms.

Pawster adds fixed Collections/61 targets, source-copy hashing, private ownership journals, inode-checked local cleanup, foreign-trash preservation, cooperative cancellation and explicit unverified receipts. No upstream Reset Collections, language switching, CarPlay, video generation, web downloads or URL-scheme handlers are imported. Nugget is an optional external UUID helper; its code is not incorporated.
