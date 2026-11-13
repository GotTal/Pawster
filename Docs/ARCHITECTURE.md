# Architecture / 架构说明

## Responsibilities

| Area | Main files | Responsibility |
| --- | --- | --- |
| UI and state | `App/ContentView.swift`, `App/AppModel.swift` | Screens, selections, operation state and settings |
| First-use setup | `App/SetupGuideView.swift`, `App/SetupProgress.swift` | LocalDevVPN, user-confirmed Developer Mode and pairing progress |
| Pairing and PiP | `App/PairingService.swift`, `App/PairingGuide.swift`, `App/PairingCredentials.swift` | Native session, temporary code display, bounded cleanup and saved-file validation |
| Connection | `App/LocalVPN.swift`, `Core/src/network.rs` | Route inspection, RSD/Lockdown and authoritative container discovery |
| Native boundary | `App/Native/Bridge.h`, `Core/include/posterbridge.h` | C-compatible interface between Swift and Rust/native access engines |
| File access | `App/AccessBroker.swift`, `App/Models.swift` | Engine policy, scoped access and container identity checks |
| Wallpapers | `App/WallpaperRepository.swift`, `App/InjectionService.swift`, `Core/src/archive.rs` | Local imports, validation, plans, transactions and rollback receipts |
| Refresh | `App/NeoSpring.swift` | Optional system UI refresh with session and cancellation controls |
| Resources | `App/Resources/`, `App/Localization.swift` | Catalogs, locale mapping, app icon and offline documents |

The UI is not a direct wrapper around an unrestricted file writer. A connection obtains the PosterBoard container, Swift validates its identity and managed directory structure, an injection plan is reviewed, and scoped file access is used to write and verify a transaction. The engine choice remains gated by `EnginePolicy`; do not widen it based only on a similar version number.

Pairing uses the Rust device protocol layer through the C interface. PiP frames are rendered locally in Swift. `worse_query` / `bad_query` grant scoped access for Swift file operations; they are not alternative network transports. Local VPN route detection alone does not prove device trust or system-service readiness.

## Start here for a change

- UI: inspect `ContentView`, its model and language keys; check English/Chinese, large text and both appearances.
- Pairing: inspect credential state, session cancellation and guide cleanup together; use fakes for repeatable lifecycle tests before trying Settings on a phone.
- Injection: follow plan, verification, receipt and rollback boundaries. Start with synthetic archive/file fixtures and read-only device inspection.
- Localization: follow [LOCALIZATION.md](LOCALIZATION.md); include corresponding app metadata and document mappings.
- Vendored code: inspect [source provenance](../ThirdParty/SOURCES.md), preserve notices and keep compatibility changes explicit.

`project.yml` generates the Xcode project. `Scripts/build-core.sh` builds iOS/simulator Rust libraries; `Scripts/test-macos.sh` runs Rust and simulator tests; `Scripts/build-ipa.sh` packages a requested build. See [CONTRIBUTING.md](../CONTRIBUTING.md) for commands and PR checks. Release signing is independent of app installation signing; private keys are not used in PR CI.

## Verification boundaries / 验证边界

Repository checks validate documents, forms, language resources and Python tooling. Native checks compile Swift, test Rust and run simulator tests. Actual Settings pairing, automatic PiP behavior, SideStore App Group rewriting, system wallpaper registration and NeoSpring effects require [device checks](实机验证步骤.md).

界面与状态由 SwiftUI/Swift 管理；Rust 通过 C 接口提供配对、设备协议和压缩包等能力。容器查询与授权引擎是不同步骤：先通过本地连接查找，再验证容器身份和目录，确认计划后才进行范围受控的文件操作。授权必须有对应释放，操作记录和取消边界必须保留。

建议先用合成文件、模拟会话和只读路径验证定位问题；模拟器测试结果与手机上的实际效果分别记录。新增系统支持需单独提供依据和实机反馈，不能从邻近版本推定。
