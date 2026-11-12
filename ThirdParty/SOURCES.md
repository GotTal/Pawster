# 第三方来源及修改

| 来源 | 固定提交 | 用途 |
|---|---|---|
| https://github.com/Mak5er/AirCard-iOS | 40640c4d827aeab8d798285b57d24fcf6be070d0 | 配对、RSD/Lockdown 连接、InstallationProxy 查询及 NeoSpring 文档；vendored idevice / idevice-ffi |
| https://github.com/forcequitOS/worse_query | d1540e20cd82b974d891e0551ced6d6aeb570ac2 | 新引擎原生授权，GPL-3.0-or-later |
| https://github.com/forcequitOS/bad_query | 73ef6da1adabef0982fd00e36cb85f21b8f8194a | 旧引擎原生授权；该快照无独立 LICENSE，公开再发行前需要核实授权 |
| https://github.com/jailbreakdotparty/Erosion | 585a24a973d1ffa33bb71e48eab59a79cca505e1 | 排查和设计参考；未复制界面或壁纸处理代码 |

AirCard-iOS 的 MIT 声明保留在 AirCard-MIT.txt。idevice 的 Cargo.toml 标注 MIT；代码来自 AirCard 的 vendor 快照，包含其 OPACK 和连接兼容性修改，不假装为未经修改的 upstream 7bd551c 源码。

本项目修改：

- 提取连接和路径查询，去除 AirTraffic / ATC / Grappa 注入代码。
- 配对和查询加入独立操作 ID、取消标志和真实异步超时；PIN 不进入日志。
- idevice-ffi 依赖改为本地 `../idevice`；使用 ring，关闭其默认 aws-lc feature。
- worse_query 补充失败分支的 query 释放和 C/ObjC 环境下的 identifier 生命周期处理；未更改授权机制。
- bad_query.h 补充 stdint.h，使头文件可独立使用。
- 原生 C / Objective-C 文件统一行尾并移除行末空白，未改变机制。
- NeoSpring HTML 改编自同一 AirCard 快照的 `ios-app/RespringHelper.swift`，保留 @neonmodder123、@skadz108 的机制署名；新增单次会话、持久化开关、取消、超时及后台清理，仅在注入成功返回并通过取消检查后自动触发。SwiftUI 更新不会反复加载文档。
- AirCard 注释另引用 `rooootdev/neospring`；本次查询该仓库未见独立许可证声明，保留为来源授权核实项，不据此宣称上游授权已全部核清。
- ZIP 和事务代码为本项目新实现。Cargo.lock 固定 crates.io 依赖。

GPL 全文位于仓库 LICENSE。此来源清单不为缺少授权声明的上游代码补造许可证。
