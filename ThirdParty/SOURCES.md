# 第三方来源及修改

| 来源 | 固定提交 | 用途 |
|---|---|---|
| https://github.com/Mak5er/AirCard-iOS | 40640c4d827aeab8d798285b57d24fcf6be070d0 | 配对、RSD/Lockdown 连接、InstallationProxy 查询、NeoSpring 文档及 AirTraffic/ATC/Grappa 目录发送；vendored idevice / idevice-ffi |
| https://github.com/forcequitOS/worse_query | d1540e20cd82b974d891e0551ced6d6aeb570ac2 | 新引擎原生授权，GPL-3.0-or-later |
| https://github.com/forcequitOS/bad_query | 73ef6da1adabef0982fd00e36cb85f21b8f8194a | 旧引擎原生授权；该快照无独立 LICENSE，公开再发行前需要核实授权 |
| https://github.com/jailbreakdotparty/Erosion | 585a24a973d1ffa33bb71e48eab59a79cca505e1 | 排查和设计参考；未复制界面或壁纸处理代码 |

AirCard-iOS 的 MIT 声明保留在 AirCard-MIT.txt。idevice 的 Cargo.toml 标注 MIT；代码来自 AirCard 的 vendor 快照，包含其 OPACK 和连接兼容性修改，不假装为未经修改的 upstream 7bd551c 源码。

本项目修改：

- 提取连接和路径查询；另从同一固定提交改编 AirTraffic 目录发送、ATC 协议辅助及 GrappaHelper，只允许向固定 Collections 路径发送新的 UUID 描述文件。新增 Books 同步状态私有备份、独立恢复、取消和超时；不移植任意路径写入、上游偏好覆盖、Wallet、拨号或系统日志功能。
- 配对和查询加入独立操作 ID、取消标志和真实异步超时；PIN 不进入日志。
- idevice-ffi 依赖改为本地 `../idevice`；使用 ring，关闭其默认 aws-lc feature。
- worse_query 补充失败分支的 query 释放和 C/ObjC 环境下的 identifier 生命周期处理；未更改授权机制。
- bad_query.h 补充 stdint.h，使头文件可独立使用。
- 原生 C / Objective-C 文件统一行尾并移除行末空白，未改变机制。
- NeoSpring HTML 改编自同一 AirCard 快照的 `ios-app/RespringHelper.swift`，保留 @neonmodder123、@skadz108 的机制署名；新增单次会话、持久化开关、取消、超时及后台清理，仅在注入成功返回并通过取消检查后自动触发。SwiftUI 更新不会反复加载文档。
- AirCard 注释另引用 `rooootdev/neospring`；本次查询该仓库未见独立许可证声明，保留为来源授权核实项，不据此宣称上游授权已全部核清。
- ZIP 和事务代码为本项目新实现。Cargo.lock 固定 crates.io 依赖。
- 本地 VPN 检测参考同一 AirCard 快照的 `NetworkStatus.swift`，保留 MIT 声明；读取接口及 UDP 路由来源，不发送探测数据包。改为核对所选 Peer 的活动隧道路由，不将任意 utun 接口视作服务已就绪；覆盖地址不使用默认对端回退。

GPL 全文位于仓库 LICENSE。此来源清单不为缺少授权声明的上游代码补造许可证。

2026-11-13 发行复核：另保留 upstream idevice 根目录 `LICENSE.txt` 的 MIT 原文于 `ThirdParty/idevice-MIT.txt` 和 App 离线资源，来源 https://github.com/jkcoxson/idevice/blob/master/LICENSE.txt （Copyright 2026 Jackson Coxson）。这补充了 idevice 已声明 MIT 的许可全文，不将当前上游文件视作 AirCard vendor 快照的逐字来源证明；idevice-ffi 快照未独立声明许可，其来源链核实仍保留。bad_query 与 NeoSpring 进一步来源的授权待核实事项也未因此消除。

## Pocket Poster / Trash

来源：https://github.com/leminlimez/Pocket-Poster，固定提交 fb07aa45586ea4d2590c6f6d258777b207e1b8c9。参考并改编 SymHandler.swift 与 PosterBoardManager.swift 中的 Collections .Trash 链接及 FileManager.trashItem 流程，原文件由 lemin 于 2025 年创建。上游将机制署名给 Nathan（verygenericname）和 DuyKhanhTran（khanhduytran0）。适配文件按 GPL-3.0-only 保留，原 GPL v3 全文位于 Pocket-Poster-GPL-3.0.txt；不改标 MIT，也不擅自添加 or-later 授权。项目自有代码保留原许可，结合各组件条款阅读。

本项目新增固定 Collections/61 目标、复制内容摘要核对、私有归属记录、inode 匹配的本地清理、外来废纸篓保护、协作式取消和明确的未校验状态。未引入上游重置集合、切换语言、CarPlay、视频生成、网页下载或 URL Scheme 处理器。Nugget 仅作为可选的外部 UUID 工具参考，未导入其代码。
