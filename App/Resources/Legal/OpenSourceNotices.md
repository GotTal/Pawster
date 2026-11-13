# 开源项目使用声明

喵贴 Pawster 由 GotTal 开发。项目及对应源码：https://github.com/GotTal/Pawster。项目代码许可：GPL-3.0-or-later；请结合各文件和第三方声明阅读，许可全文可在上一页查看。用户协议不减少开源许可赋予的权利。

## AirCard-iOS

来源：https://github.com/Mak5er/AirCard-iOS，固定提交 40640c4d827aeab8d798285b57d24fcf6be070d0。参考并改编配对、RSD/Lockdown、InstallationProxy 容器查询，以及 RespringHelper 中的 NeoSpring HTML；保留其 MIT 版权声明（2026 Johnny Franks）与许可全文。

## worse_query 与 bad_query

worse_query：https://github.com/forcequitOS/worse_query，提交 d1540e20cd82b974d891e0551ced6d6aeb570ac2，GPL-3.0-or-later；用于新版引擎文件访问授权，修改了失败分支的释放与标识生命周期。

bad_query：https://github.com/forcequitOS/bad_query，提交 73ef6da1adabef0982fd00e36cb85f21b8f8194a，用于旧版引擎。该来源快照未找到独立 LICENSE，授权范围有待核实；本声明不替上游补造许可，也不将“可公开访问”等同于“可自由再发行”。

## idevice / idevice-ffi 与 Rust 依赖

设备协议代码来自上述 AirCard 快照中的 vendor，包含其兼容性修改。idevice 包作者标为 Jackson Coxson，Cargo.toml 声明 MIT；idevice-ffi 快照未独立声明许可证，仍需结合原作者及来源核实授权。Rust 依赖清单按 Cargo.lock 与缓存包元数据生成，涵盖开发和多平台依赖，并非全部都进入 iOS 成品。各包适用各自许可，不统一改为 GPL。

## NeoSpring 的进一步来源

AirCard 注释将机制署名给 @neonmodder123、@skadz108，并另引用 https://github.com/rooootdev/neospring。本项目保留该署名，加入会话、取消、超时和自动刷新控制。此次来源核对未见该进一步来源的独立许可证，列为授权核实项。

## Erosion 与壁纸内容

https://github.com/jailbreakdotparty/Erosion，提交 585a24a973d1ffa33bb71e48eab59a79cca505e1，为排查和设计参考，未复制其界面或壁纸处理代码。用户导入的壁纸包及其中图像、动画、字体等不随本项目取得开源许可，由相应权利人决定授权。

## 再分发说明

修改概述、固定来源和依赖清单可在本页返回后的对应栏目查看。缺失授权的项目仍是公开再分发前应解决的事项；列出来源不代表已完成全面许可证审计。构建或发行者应提供适用许可、版权声明和对应源码，并核实全部授权及修改义务。

AirTraffic/Airlift 补充来源：沿用上述 AirCard 固定提交中的 rust-core/src/exploit.rs（目录发送及协议辅助）、grappa.rs 和 ios-app/GrappaHelper.[hm]；保留 MIT 许可。新增固定 Collections 目标、源文件链接检查、取消与超时、Books 状态备份和恢复，以及“已发送、目标未校验”记录；不提供上游任意路径写入或偏好文件覆盖接口。

## Pocket Poster / Trash

来源：https://github.com/leminlimez/Pocket-Poster，固定提交 fb07aa45586ea4d2590c6f6d258777b207e1b8c9。参考并改编 SymHandler.swift 与 PosterBoardManager.swift 中的 Collections .Trash 链接及 FileManager.trashItem 流程，原文件由 lemin 于 2025 年创建。上游将机制署名给 Nathan（verygenericname）和 DuyKhanhTran（khanhduytran0）。适配文件按 GPL-3.0-only 保留，原 GPL v3 全文位于 Pocket-Poster-GPL-3.0.txt；不改标 MIT，也不擅自添加 or-later 授权。项目自有代码保留原许可，结合各组件条款阅读。

本项目新增固定 Collections/61 目标、复制内容摘要核对、私有归属记录、inode 匹配的本地清理、外来废纸篓保护、协作式取消和明确的未校验状态。未引入上游重置集合、切换语言、CarPlay、视频生成、网页下载或 URL Scheme 处理器。Nugget 仅作为可选的外部 UUID 工具参考，未导入其代码。
