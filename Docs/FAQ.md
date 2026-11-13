# Frequently Asked Questions / 常见问题

## Where do I download Pawster? / 去哪里下载？

Use [the latest Release](https://github.com/GotTal/Pawster/releases/latest). Download the IPA and matching verification assets from the same release. See [file verification](VERIFYING_RELEASES.md). SideStore re-signing is still needed for installation. Test and release builds replace one another because they share an app identifier.

请从最新 Release 获取 IPA，并下载同一版本的验签附件。先验证原始文件，再通过 SideStore 重签安装；测试版与正式版不能并存。

## Which devices and systems work? / 支持哪些设备和系统？

See the [compatibility table](COMPATIBILITY.md). A listed engine path is not a guarantee that every device has been tested. Include the full iOS build number in device reports, especially for betas.

查看兼容性表，区分“代码允许的路径”和“已完成实测的组合”；反馈时附完整系统构建号，尤其是 beta。

## VPN is connected, but the path query fails / VPN 已连接，为什么查不到路径？

The badge confirms a route to the selected peer, not pairing trust or service readiness. Keep the device unlocked, confirm LocalDevVPN is connected, and check that Pawster's Peer IP matches LocalDevVPN's Device IP. Try the read-only path query; if it fails, capture the exact error. A changed peer override can make an otherwise working route invalid.

状态徽章只能说明检测到相应路由。保持解锁，检查本地 VPN 与对端地址，再执行“自动查询并只读验证路径”。记录具体错误，不要将旧容器 UUID 当作固定地址。

## The pairing file is ready, but connection fails / 配对文件已就绪，为什么仍然失败？

Ready means the local file format passed validation. The device must still accept the credentials. Reconnect VPN and run the read-only query; replace the file or pair again if the device rejects it. On-device pairing is only exposed on the supported system path described in the README.

“已就绪”表示本地格式有效，仍需设备接受其凭据。重新连接 VPN 后只读查询；明确被拒绝时再替换配对文件或重新配对。本机配对入口以 README 和 App 支持范围为准。

## The guide window does not open / 配对小窗没有出现怎么办？

Automatic PiP depends on system behavior and settings. Return to Pawster to view or copy the current code. The live code appears after the device requests pairing; never post it publicly. If the window remains after completion, record whether it closes after returning to Pawster and report the build and steps without the code.

自动画中画受系统设置与行为影响。可以返回 App 查看或复制当前配对码；真实配对码在系统发起配对后出现。小窗未正常关闭时，记录切回 App 后的表现和复现步骤，截图前隐藏配对码。

## The wallpaper is not listed after installation / 注入后没有显示新壁纸？

First check whether the operation completed and content verification passed. For a completed installation, use Settings → Operation History → Back Up and Refresh Registration if needed, then inspect the system wallpaper picker. NeoSpring is a separate optional UI refresh; it does not repair failed writes. Preserve the operation record when reporting an error.

先看操作是否完成并通过内容校验。已完成的操作可按需使用“设置 → 操作记录 → 备份并刷新注册”，再检查系统列表。NeoSpring 属于可选界面刷新，不能修复失败的写入；反馈时保留对应操作记录。

## What does NeoSpring do? / NeoSpring 是什么？

It attempts to refresh the system interface. The screen may briefly go black, return to the Lock Screen or close Pawster. Manual refresh asks for confirmation; automatic refresh is optional and follows a verified installation. Save current work before confirming.

它用于尝试刷新系统界面，可能短暂黑屏、返回锁屏或使 App 退出。手动操作需确认，自动刷新为可选项，并在注入及校验成功后触发；确认前请保存当前工作。

## Does deleting a pack remove its installed wallpaper? / 删除导入包会卸载壁纸吗？

Swiping left removes Pawster's local imported copy. Use the corresponding operation history entry to roll back an installation. If installed files have changed, rollback stops for review.

左划只删除本地导入副本。撤回安装请使用对应操作记录；相关文件发生变化时会停止撤回，留待检查。

## How should I report a problem? / 如何反馈？

Use the [bug form](https://github.com/GotTal/Pawster/issues/new?template=bug_report.yml). Include the app version, device model, full iOS version/build, installation method and exact steps. Enable diagnostic logging in Settings only when needed and inspect it before sharing. Never attach working pairing files, PINs or private wallpaper packs. Security-sensitive reports belong in [private reporting](../SECURITY.md).

使用错误表单，附版本、机型、完整系统构建号、安装方式和复现步骤。按需开启诊断，分享前检查并脱敏；不要上传有效凭据、PIN 或私人壁纸包。安全问题通过私密渠道报告。
