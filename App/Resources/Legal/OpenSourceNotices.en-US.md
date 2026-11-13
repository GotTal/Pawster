# Open-source Notices

Pawster is developed by GotTal. Project and corresponding source: https://github.com/GotTal/Pawster. Project code is licensed under GPL-3.0-or-later; also consult individual files and third-party notices. The full license is available on the previous page. The Terms of Use do not reduce rights granted by open-source licenses.

## AirCard-iOS

Source: https://github.com/Mak5er/AirCard-iOS, pinned commit 40640c4d827aeab8d798285b57d24fcf6be070d0. Pairing, RSD/Lockdown, InstallationProxy container queries, and the NeoSpring HTML from RespringHelper were referenced and adapted. Its MIT copyright notice (2026 Johnny Franks) and full license are retained.

## worse_query and bad_query

worse_query: https://github.com/forcequitOS/worse_query, commit d1540e20cd82b974d891e0551ced6d6aeb570ac2, GPL-3.0-or-later. It authorizes file access for the newer engine. Changes address release on failure paths and identifier lifetimes.

bad_query: https://github.com/forcequitOS/bad_query, commit 73ef6da1adabef0982fd00e36cb85f21b8f8194a, used for the older engine. No standalone LICENSE was found in this snapshot; authorization remains to be verified. This notice does not supply missing permission or equate public availability with permission to redistribute.

## idevice / idevice-ffi and Rust dependencies

Device protocol code comes from vendor in the pinned AirCard snapshot and includes its compatibility changes. idevice lists Jackson Coxson as author and MIT in Cargo.toml. The idevice-ffi snapshot does not independently declare a license; authorization must be verified with the original author and source. The Rust inventory is generated from Cargo.lock and cached package metadata. It includes development and multiple-platform packages; not all enter the iOS binary. Each dependency retains its applicable license and is not uniformly relicensed as GPL.

## Further NeoSpring sources

AirCard comments credit @neonmodder123 and @skadz108 for the mechanism and reference https://github.com/rooootdev/neospring. Pawster retains that credit and adds session, cancellation, timeout, and automatic refresh controls. No standalone license for that further source was found in this review; authorization remains to be verified.

## Erosion and wallpaper content

https://github.com/jailbreakdotparty/Erosion, commit 585a24a973d1ffa33bb71e48eab59a79cca505e1, was a debugging and design reference. Its interface and wallpaper handling code were not copied. Wallpaper packs imported by users, including images, animation, and fonts, do not acquire an open-source license from this project. Their rights holders determine permission.

## Redistribution

Return to the previous page for modification notes, pinned sources, and dependency inventories. Missing authorization must be resolved before public redistribution. Listing sources does not establish a complete license audit. Builders and distributors must supply applicable licenses, copyright notices, and corresponding source, and verify all permissions and modification obligations.

AirTraffic/Airlift additionally adapts rust-core/src/exploit.rs (folder transport and protocol helpers), grappa.rs and ios-app/GrappaHelper.[hm] from the same AirCard source pin under its retained MIT notice. Destinations are limited to new Collections descriptor UUIDs, with source validation, cancellation/timeouts, Books sync backup/recovery and explicit unverified results. Generic writes and preference replacement are not exposed.

## Pocket Poster / Trash

Source: https://github.com/leminlimez/Pocket-Poster, pinned commit fb07aa45586ea4d2590c6f6d258777b207e1b8c9. Adapted the Collections .Trash-link and FileManager.trashItem flow from SymHandler.swift and PosterBoardManager.swift, created by lemin in 2025. Upstream credits Nathan (verygenericname) and DuyKhanhTran (khanhduytran0) for the exploit. The adapter retains GPL-3.0-only treatment and the unmodified upstream GPL v3 text in Pocket-Poster-GPL-3.0.txt; it is not relabeled as MIT or automatically granted an or-later permission. Project-owned code retains its existing license, subject to each component’s terms.

Pawster adds fixed Collections/61 targets, source-copy hashing, private ownership journals, inode-checked local cleanup, foreign-trash preservation, cooperative cancellation and explicit unverified receipts. No upstream Reset Collections, language switching, CarPlay, video generation, web downloads or URL-scheme handlers are imported. Nugget is an optional external UUID helper; its code is not incorporated.
