# 喵贴 Pawster 0.1.1 · 测试分支

> 当前为 `testing/pairing-pip` 测试分支。后续修复先在测试分支构建并验证；自动测试通过后，还需用户实机确认，才准备合并到 main 和更新正式版本。当前 main 保留此前的 0.1.1，不自动合并或改版本。
>
> 测试 IPA 的名称包含 `-test.<构建号>-<提交>`，安装后中文显示“喵贴测试版”、英语显示“Pawster Test”，保留原 Bundle ID 和 App Group 以便覆盖测试。测试包与正式包不能同时安装；原有配置通常可沿用。正式营销版本号暂不提高。

最新测试包：[Pawster-0.1.1-test.7-a6ce9aa](https://github.com/GotTal/Pawster/actions/runs/43191857499/artifacts/13931643370)（需登录 GitHub，保留至 2026-11-26）。[本次 CI](https://github.com/GotTal/Pawster/actions/runs/43191857499) 的 9 项 Rust、50 项 Swift 测试全部通过；测试身份、构建号 7、来源提交、中英离线资源、图标和下载完整性已核验，真实设备验收仍待用户确认。主分支保持 `6d18c46`，未合并。

测试 IPA SHA-256：`2afe238edd71585c13a0fe245fa86f06247b9d9544c7bf8f9954f3bd5935f05d`。

独立的 iOS Collections 壁纸注入工具。使用 AirCard-iOS 的配对和 InstallationProxy 查询流程发现 PosterBoard 容器；文件访问分别采用 bad_query / worse_query。支持简体中文和美式英语，兼容 SideStore 重签后的实际 App Group 标识。

**这是实机待验证的测试版。GitHub Actions 已完成编译、9 项 Rust 测试和 50 项 Swift 模拟器测试，并生成 IPA；测试通过不能代替跨 App 小窗、真实配对、壁纸注入与 NeoSpring 的目标手机验收。**

[此前 main 的 0.1.1 构建产物](https://github.com/GotTal/Pawster/actions/runs/43147638264/artifacts/13913006540)（需登录 GitHub，保留至 2026-11-26）。解压得到 `Pawster-0.1.1.ipa`，通过 SideStore 使用自己的账号重签安装。[构建与测试记录](https://github.com/GotTal/Pawster/actions/runs/43147638264)。

IPA SHA-256：`b70dae111d953ed38b7e4c16f3fb83fe67aee7a2de82a4fb095e6fa36bda6874`。

## 分支与发布顺序

test.7 之后的当前工作区修改尚未打包：壁纸包删除手势已改为左划；连接页新增本地VPN路由状态、Iface IP、Peer IP和可保存/清空的覆盖地址；手动覆盖只使用指定目标。壁纸页以“预览并注入壁纸”为通栏主入口，“刷新系统界面（NeoSpring）”移至可选分区。手动刷新每次说明并确认；自动刷新首次勾选确认后，后续写入校验成功直接执行。新增中英词条后当前源码语言包各301条，旧test.7仍为276条。按本轮要求未推送或构建新IPA；本机12项Rust测试通过，新增Swift测试及界面效果仍需Xcode/实机验证。

1. 在 `testing/**` 分支提交修复，或手动选择对应分支运行 Actions。测试分支生成明确标记的测试 IPA。
2. 先完成 CI，再按实机验证步骤检查真实配对、小窗渲染、自动开关、路径查询，以及注入和撤回。记录失败继续修复，不把 CI 通过当作实机验收。
3. 用户明确确认全部待修问题已解决后，准备合并到 main 的变更，再更新正式版本号和说明并构建正式包。

CI 只有仓库只读权限，没有自动合并或发布 Release 的步骤。新测试包见 [本分支构建记录](https://github.com/GotTal/Pawster/actions?query=branch%3Atesting%2Fpairing-pip)。

test.7 已包含本轮修改：主导航为“壁纸 / 连接 / 设置”，“操作记录”和“诊断”移入设置。设置新增外观、可选诊断日志保留条数（默认不记录）、清除日志、移除配对凭据及撤回授权；底部关于包含版本、GotTal、项目与联系入口、离线开源声明、用户协议和隐私政策。首次启用和配对处理均需明确选择。注入复制校验、壁纸包删除、手动/自动 NeoSpring 及猫咪图标也已进入测试包。

美式英语与现有简体中文语言包覆盖页面、配对小窗、状态、错误提示和离线说明，各含276个词条。按设备首选语言自动选择：中文优先匹配地区/文字包，未提供时回落简体中文；其他语言优先匹配已登记的包，否则回落美式英语。新中文包缺词条也先回落简体中文，其他语言缺词条回落英语。语言映射、翻译格式与校验方式见 [本地化贡献规范 / Localization Guide](Docs/LOCALIZATION.md)。映射、占位符及资源打包测试已通过，真实设备显示仍待确认。

法律文本依据和数据行为核对见 [法律文件说明](Docs/法律文件说明.md)。这是随源码提供的数据处理告知，不是合规认证；bad_query、NeoSpring 进一步来源和部分依赖授权仍需在公开再分发前核实。

## 已实现

- 手动 NeoSpring 和“自动 NeoSpring”复选框（默认关闭、保存用户选择）。仅在本次壁纸写入、校验及操作记录保存成功后自动触发；失败或取消不触发。6项会话控制测试通过，真实系统刷新仍需实机验证。
- 导入配对文件；iOS 27 本机配对、Bonjour 广播、六位 PIN 回调、180 秒超时和可真正结束 Rust 等待的取消操作。
- 自动画中画配对引导：配对期间离开 App 自动弹出，显示设置步骤、实时配对码与剩余时间，不提供手动开窗按钮。配对成功后清除 PIN、显示“配对成功”，3 秒后自动关闭小窗和音频保活。失败也显示结果后关闭。系统仍可能拒绝自动画中画；应用内始终保留同一份预览。
- RSD RemoteXPC / raw RPPairing 与旧式 Lockdown 连接，按 `com.apple.PosterBoard` 查询 `Container`，35 秒查询超时。
- 只读核验路径、MCM 元数据、xattr 存在性与错误码。缺少 xattr 不会推翻可靠的系统查询；身份冲突时拒绝使用路径。
- `.tendies` 安全解压、结构分析、plist 与已知文件引用检查、Collections 预览和重复包识别。
- 注入前预览目标及引擎，重新查询路径；保持内部标识不变，在已有 Collections 提供组件目录中新增随机 UUID 描述文件目录。
- 同一父目录内临时复制、SHA-256 内容校验、改名提交；先保存日志再修改目标。中途取消或异常保留可检查的操作记录。
- 撤回只处理本次记录，检测后来修改过的内容并停止删除。整容器替换、数据库覆盖及 Reset Collections 均未提供。
- 可选的注册刷新：备份并合并容器内偏好，不覆盖其他键、不修改全局 mobile 偏好；撤回时检查原备份和当前文件，避免覆盖外部更改。

## 系统选择

| 系统 | 首版策略 | 真机状态 |
|---|---|---|
| iOS 26.0–26.6.1 | bad_query | 待验证 |
| iOS 27.0 beta 4 | 用户明确确认 beta 4 后使用 bad_query | 待验证；系统版本 API 不区分同一版本号的 beta 构建 |
| iOS 27.2.1 | worse_query，首要验证目标 | 待验证 |
| 其他系统 | 阻止注入 | 未列入首版范围 |

版本范围来自上游声明及本项目需求，不代表兼容性承诺。完整系统版本字符串记录在诊断中。不会在部分写入后切换引擎。

## 在 Mac 上构建

需要 macOS、含 iOS 26 或以上 SDK 的 Xcode、Rust stable、XcodeGen。所有源代码和网络依赖的本地修改均在仓库内；Cargo.lock 固定 Rust 依赖。

```bash
bash Scripts/build-core.sh
bash Scripts/build-ipa.sh
```

本地默认生成测试包，IPA 位于 `build/Packages/Pawster-0.1.1-test.local-<提交>.ipa`。脚本只进行本地构建和 ad-hoc 签名；安装时由 SideStore 使用你的账号重签。worse_query 使用专用的 `group.io.github.gottal.Pawster.WQ` 应用组，运行时读取重签后的实际标识；不使用 SideStore 自己的应用组。

运行测试：

```bash
cargo test --locked --manifest-path Core/Cargo.toml --features device
TEST_DESTINATION='platform=iOS Simulator,name=你的模拟器名称' bash Scripts/test-macos.sh
```

模拟器不能验证沙箱访问、系统配对、壁纸注册或画中画跨 App 显示。详见 [验证记录](Docs/验证记录.md) 和 [实机验证步骤](Docs/实机验证步骤.md)。

### 没有 Mac 时

仓库包含推送 main 后自动运行、也可手动触发的 GitHub Actions 工作流。在本仓库的 Actions 中运行 `Build and test Pawster`，它会使用 macOS runner 执行 Rust 测试、Swift 模拟器测试并打包 IPA。仅在所有步骤通过后上传 IPA。工作流只有仓库只读权限；最初导入源码的一次性写入步骤已移除。构建状态以 Actions 的实际结果为准。

## 使用顺序

1. 连接 LocalDevVPN，导入已有配对文件；或在 iOS 27 上“开始本机配对”。
2. 本机配对时先确认 App 顶部引导画面正常，再离开 App，小窗会自动弹出。前往“设置 → 隐私与安全性 → 开发者模式 → 与 Pawster 配对”；收到 PIN 后在系统页面输入。没有 PIN 时，小窗显示等待，不显示示例码。配对成功后显示成功文字，3 秒后自动关闭。
3. 返回 App，“自动查询并只读验证路径”。此阶段不修改 PosterBoard 的文件；授权机制会使用本工具专用 App Group 的临时 Caches 链接。
4. 导入并选择 `.tendies`，检查注入计划，再确认注入。
5. 文件校验完成后，到系统壁纸界面检查；如需刷新注册，在“设置 → 操作记录”中单独执行“备份并刷新注册”。本工具不自动重启手机或清空壁纸。
6. 若不需要本次内容，使用对应记录的“撤回这次注入”。有外部修改时会停止，保留现场。

## 架构

- `App/PairingService.swift`：配对生命周期、配对文件及查询入口。
- `App/PairingGuide.swift`：画中画引导和应用内回退。
- `App/NeoSpring.swift`：本地 WebKit NeoSpring 文档、会话及超时清理、自动选项持久化。
- `App/AccessBroker.swift`：双引擎作用域及身份诊断；非负句柄（含 0）均按作用域释放。
- `App/WallpaperRepository.swift`：导入、结构分析、资源引用和内容哈希。
- `App/InjectionService.swift`：计划、提交、恢复、注册备份合并。
- `Core/src/network.rs`：从 AirCard-iOS 提取的连接和 InstallationProxy 查询代码，不包含 AirTraffic 注入流程。
- `Core/src/pairing.rs` / `operations.rs`：配对协议与取消、超时控制。
- `Core/src/archive.rs`：有大小限制的 ZIP 提取，拒绝越界路径、符号链接和名称冲突。

## 当前边界

只支持首版系统表及 Collections `.tendies`。不推断未注册的存储版本，不创建缺失的系统提供组件目录；多个可用存储版本并存时停止。保持包内现有标识意味着内部标识相同的不同包仍可能冲突；系统注册可见性必须实测。

画中画不代替用户操作“设置”，也不会识别用户当前所在设置页面。公开设置跳转仅打开本 App 的设置页。配对期间会开启静音音频保活，结束或超时后显示结果约 3 秒，再关闭小窗并停止保活；这是需要真机验证的侧载工具行为。

仓库采用 GPL-3.0-or-later，保留第三方原有声明。上游版本及授权信息见 [第三方来源](ThirdParty/SOURCES.md)。

`SOURCE_MANIFEST.json` 记录最初源码导入时的快照，不作为后续提交的清单；后续修改以 Git 提交为准。main 的 0.1.1 基线 IPA 对应提交 `211088ad4ba74696d6a1dce81d69733c833bbd86`；本测试分支首次带测试标识的构建对应 `e5bf9cba2e05697c43f0819dbf57ae93b38ef218`。
