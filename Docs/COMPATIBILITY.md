# Compatibility and Device Reports / 兼容性与实机反馈

The table describes the current engine policy, not universal device acceptance. The minimum deployment target does not imply that every later iOS version is supported.

| iOS | Engine path enabled by code | Pairing path | Device validation status |
| --- | --- | --- | --- |
| 17.0–18.7.2 | Experimental Pocket Poster / Trash | Manual UUID; imported pairing optional for discovery | Source integration only; not compiled or device-validated |
| 26.0–26.1 | `worse_query` default; `bad_query` or experimental Pocket / Trash | Imported file for discovery; Pocket can use manual UUID | Pocket transfer remains unverified |
| 26.1.1–26.6.1 | `worse_query` default; `bad_query` selectable | Imported file only | Community validation requested for both scoped engines |
| 26.6.2–26.7.2 | `worse_query` | Imported file only | Community validation requested |
| 27.0 beta 4 (`24A5390f`) | `worse_query` default; `bad_query` or experimental AirTraffic | Native or imported | Exact build required for `bad_query`; AirTraffic remains unverified |
| 27.0–27.0.1; 27.2 beta 1/2 (`24B5084k`, `24B5089g`) | `worse_query` default; experimental AirTraffic selectable | Native or imported | AirTraffic sends only; see its limitations below |
| 27.0–27.2.1, including 27.2 beta 1–2 | `worse_query` | Native or imported | Earlier 27.2.1 feedback exists; full current-release acceptance remains unconfirmed |
| 27.3 beta 1 (`24C5037i`) | `worse_query` | Native or imported | Exact kernel build required; no other 27.3 build enabled |
| Other versions | Installation blocked | Pairing availability alone is not wallpaper support | Not claimed supported |

当前表格描述代码启用的访问路径，不代表每个机型均已验收。历史反馈不能替代当前版本的完整实测，最低部署版本也不代表之后所有系统都可注入。

## Source review / 来源复核

Reviewed on 2026-11-13. These are separate capabilities: path discovery through system services, Settings pairing, and file-access authorization. A working pairing session is not proof of a working injection engine.

Pocket Poster/Trash adds an older-system source policy based on the original repository, not the later worse_query forks. The app/framework minimum is now iOS 17.0. The 18.x branch stops at 18.7.2 conservatively; later backport claims are not assumed. See [Pocket Poster sources, setup and cleanup](POCKET_POSTER.md). A manual UUID is format-checked only and bypasses mandatory VPN/pairing; directory inspection, target verification and wallpaper rollback remain unavailable on this path.

- [AirCard README](https://github.com/Mak5er/AirCard-iOS/blob/40640c4d827aeab8d798285b57d24fcf6be070d0/README.md) lists native/imported pairing and Tendies on 27.0–27.0.1 and 27.2 beta 1–2, with imported pairing on older systems. Its [TendiesEngine](https://github.com/Mak5er/AirCard-iOS/blob/40640c4d827aeab8d798285b57d24fcf6be070d0/ios-app/TendiesEngine.swift) calls Airlift/AirTraffic, implemented in [exploit.rs](https://github.com/Mak5er/AirCard-iOS/blob/40640c4d827aeab8d798285b57d24fcf6be070d0/rust-core/src/exploit.rs). That is not `bad_query`. Its 27.2 beta 3 Airlift patch boundary does not define Pawster's `worse_query` boundary.
- [bad_query README](https://github.com/forcequitOS/bad_query/blob/73ef6da1adabef0982fd00e36cb85f21b8f8194a/README.md) lists 26.0–26.6.1 and 27.0 beta 4. Pawster retains this narrower engine-specific policy. [Erosion 0.2.1](https://github.com/jailbreakdotparty/Erosion/blob/6f39c552d6a68425aaeeff04bd148a8ee3069319/README.md) identifies beta 4 as `24A5390f`; its broader historical bad_query claims do not widen this policy.
- [worse_query README](https://github.com/forcequitOS/worse_query/blob/d1540e20cd82b974d891e0551ced6d6aeb570ac2/README.md) lists 26.0–26.7.2 and the 27.2 line, requires a usable App Group, and includes Application Data paths. [Erosion's current README](https://github.com/jailbreakdotparty/Erosion/blob/585a24a973d1ffa33bb71e48eab59a79cca505e1/README.md) adds 27.2.1 and 27.3 beta 1 (`24C5037i`). Its header says 26.7.2 while its detailed list still ends at 26.6.2; [release 0.3](https://github.com/jailbreakdotparty/Erosion/releases/tag/0.3) also states 26.7.2. Pawster uses the engine upstream's 26.7.2 limit, without interpreting an old statement about all available versions as future support.

Both scoped-engine HEADs match the existing source pins at review time. Their authorization implementations remain pinned. An experimental AirTraffic folder transport is adapted from the same AirCard source pin; see [AirTraffic scope and recovery](AIRLIFT.md).

AirCard 的壁纸版本表对应 AirTraffic/Airlift，不能据此认定 bad_query 支持 27.0 正式版或 27.2 beta。worse_query 已覆盖这些版本；26.6.2–26.7.2 也按其上游范围启用。27.3 例外只认 `24C5037i`，不会扩大到整个 27.3 分支。这里只调整壁纸文件访问，不宣称兼容其他项目中的全部功能。

## Selection and pairing / 引擎选择与配对

AirTraffic is also selectable on its listed Tendies builds without an App Group. It does not extend the enabled OS range or provide target inspection, installed-file verification, preference merging, automatic wallpaper rollback or automatic NeoSpring. Its Books synchronization recovery is separate from wallpaper rollback. See [the transport details](AIRLIFT.md).

On systems with both engines, **Connection → Paths & Compatibility** offers a selector. The initial choice is `worse_query`; a manual choice is retained for the current OS version/build. After a system change, a new build starts with the default. Switching clears the verified container and plan, so path verification and preview must run again. An authorization failure does not silently try another engine. A missing `Pawster.WQ` App Group remains an actionable signing error.

Plans must use the currently selected compatible engine. Registration refresh and rollback retain the engine in their original receipt and check its current compatibility before system access. Choosing another engine does not rewrite history or bypass a now-unsupported engine. The file-access boundary also rechecks compatibility before granting access.

iOS 26 uses imported credentials only. Connection hides native pairing controls and Settings pairing instructions; Getting Started describes importing a file for the same device. The backend also refuses native pairing without starting a session or replacing saved credentials. Developer Mode instructions remain relevant to sideloaded apps. iOS 27 keeps both native Settings pairing and imported credentials. These checks do not waive VPN, consent, credential validation, or service availability requirements.

双引擎系统默认 worse_query，手动选择按系统构建保存在本机；切换需重新验路径、生成计划。历史撤回/注册刷新继续使用原记录引擎，系统升级导致原引擎不兼容时会先行拒绝。iOS 26 在教程、连接页及后端均采用导入文件路径，不显示无法使用的本机配对设置步骤。

Local resource and syntax checks are separate from native tests and device acceptance. This review has not built an IPA or executed the expanded native test cases. Follow [device validation](实机验证步骤.md) before claiming successful use on additional versions.

## Share a device report / 提交实测

Use the [compatibility form](https://github.com/GotTal/Pawster/issues/new?template=compatibility_report.yml). Record these independently: SideStore installation/App Group, VPN route, read-only path verification, pairing, PiP opening and closing, write verification, registration/visibility, rollback and optional NeoSpring. Use `passed`, `failed` or `not tested`; distinguish imported pairing from native pairing.

按机型、完整系统构建号、App 版本/提交和安装方式分别记录。请先按[实机步骤](实机验证步骤.md)做只读检查，写入、撤回和 NeoSpring 仅在自己明确选择且有合适测试内容时验证；未执行的项目记为“未测试”。无需提供设备序列号、UDID、实时配对码或实际凭据。

Maintainers can add concise, linked report rows here after checking the evidence. A report applies to its exact configuration; conflicting results remain visible rather than being turned into a blanket support claim.
