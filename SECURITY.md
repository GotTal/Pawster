# Security Policy / 安全问题报告

## Supported versions

Security fixes target the latest stable Release and current `main`. Older releases do not have a separate maintenance commitment. Supported iOS installation paths remain those documented in the [README](README.md#compatibility); app maintenance does not imply compatibility with additional iOS versions.

## Report privately

Use [GitHub private vulnerability reporting](https://github.com/GotTal/Pawster/security/advisories/new) when available, or email GotTal at [xkstudio@icloud.com](mailto:xkstudio@icloud.com). For a security issue, share the affected version/commit, impact, reproduction steps and a minimal synthetic example privately. Keep working pairing credentials, live codes, signing keys and personal wallpaper content out of reports. A statement that sensitive material exists is enough to start the discussion.

Archive path escape, unintended system-file writes, credential disclosure, scoped-access cleanup and release-file verification are relevant areas. Ordinary setup failures and unsupported systems can use the public bug form with sanitized information. Upstream iOS access mechanisms and known system-version limitations are documented dependencies; explain any new impact specific to Pawster.

GotTal will assess reports as time permits, coordinate fixes and disclosure with the reporter where possible, and credit contributors with their agreement. There is no promised response deadline, bounty or guarantee of a fix. Do not use other people's devices or data to investigate an issue.

## 中文说明

安全修复面向最新正式 Release 与当前 main，旧版本暂无独立维护承诺；可用系统范围仍以 README 为准。

请优先使用 GitHub 私密漏洞报告入口（可用时），或邮件联系 [xkstudio@icloud.com](mailto:xkstudio@icloud.com)。私下说明受影响版本、影响、复现步骤与最小合成示例。不要附带有效配对凭据、实时配对码、签名私钥或私人壁纸；可以先说明存在敏感材料，再讨论必要的安全交接方式。

压缩包路径越界、意外写入系统文件、凭据泄露、访问授权清理和发布验签均属于相关问题。普通设置失败和不支持的系统可使用公开错误表单，并先脱敏。涉及上游访问机制时，请说明对喵贴新增的实际影响。

GotTal 会在可用时间内评估报告，并尽可能协商修复与披露；署名需经报告者同意。不承诺固定响应期限、奖励或一定能修复。研究时请使用自己的设备与数据。
