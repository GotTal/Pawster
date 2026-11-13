# Compatibility and Device Reports / 兼容性与实机反馈

The table describes the current engine policy, not universal device acceptance. The minimum deployment target does not imply that every later iOS version is supported.

| iOS | Engine path enabled by code | Pairing path | Device validation status |
| --- | --- | --- | --- |
| 26.0–26.6.1 | `bad_query` | Imported file | Community validation requested |
| 27.0 beta 4 | `bad_query`, with explicit exact-beta confirmation | Native or imported | Community validation requested; nearby builds are not included |
| 27.2.1 | `worse_query` | Native or imported | Earlier device feedback exists; full current-release acceptance remains unconfirmed |
| Other versions | Installation blocked | Pairing availability alone is not wallpaper support | Not claimed supported |

当前表格描述代码启用的访问路径，不代表每个机型均已验收。历史反馈不能替代当前版本的完整实测，最低部署版本也不代表之后所有系统都可注入。

## Share a device report / 提交实测

Use the [compatibility form](https://github.com/GotTal/Pawster/issues/new?template=compatibility_report.yml). Record these independently: SideStore installation/App Group, VPN route, read-only path verification, pairing, PiP opening and closing, write verification, registration/visibility, rollback and optional NeoSpring. Use `passed`, `failed` or `not tested`; distinguish imported pairing from native pairing.

按机型、完整系统构建号、App 版本/提交和安装方式分别记录。请先按[实机步骤](实机验证步骤.md)做只读检查，写入、撤回和 NeoSpring 仅在自己明确选择且有合适测试内容时验证；未执行的项目记为“未测试”。无需提供设备序列号、UDID、实时配对码或实际凭据。

Maintainers can add concise, linked report rows here after checking the evidence. A report applies to its exact configuration; conflicting results remain visible rather than being turned into a blanket support claim.
