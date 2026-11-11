# 喵贴 Pawster 0.1.0

独立的 iOS Collections 壁纸注入工具。使用 AirCard-iOS 的配对和 InstallationProxy 查询流程发现 PosterBoard 容器；文件访问分别采用 bad_query / worse_query。界面为中文，兼容 SideStore 重签后的实际 App Group 标识。

**这是源码开发版。当前尚未在 macOS/Xcode 中编译，也未连接 iPhone 验证；不要将本机测试通过理解为注入已在真机成功。**

## 已实现

- 导入配对文件；iOS 27 本机配对、Bonjour 广播、六位 PIN 回调、180 秒超时和可真正结束 Rust 等待的取消操作。
- 画中画配对引导：设置路径、配对项名称、实时配对码、剩余时间。配对结束清除显示及通过复制按钮保存的剪贴板内容。此功能待真机验证；系统可能拒绝启动 PiP。
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

IPA 位于 `build/Packages/Pawster-0.1.0.ipa`。脚本只进行本地构建和 ad-hoc 签名；安装时由 SideStore 使用你的账号重签。worse_query 使用专用的 `group.io.github.gottal.Pawster.WQ` 应用组，运行时读取重签后的实际标识；不使用 SideStore 自己的应用组。

运行测试：

```bash
cargo test --locked --manifest-path Core/Cargo.toml --features device
TEST_DESTINATION='platform=iOS Simulator,name=你的模拟器名称' bash Scripts/test-macos.sh
```

模拟器不能验证沙箱访问、系统配对、壁纸注册或画中画跨 App 显示。详见 [验证记录](Docs/验证记录.md) 和 [实机验证步骤](Docs/实机验证步骤.md)。

### 没有 Mac 时

仓库包含推送 main 后自动运行、也可手动触发的 GitHub Actions 工作流。将源码放入你自己的 GitHub 仓库后，在 Actions 中运行 `Build and test Pawster`，它会使用 macOS runner 执行 Rust 测试、Swift 模拟器测试并打包 IPA。仅在所有步骤通过后上传 IPA。构建状态以本仓库 Actions 的实际结果为准。

## 使用顺序

1. 连接 LocalDevVPN，导入已有配对文件；或在 iOS 27 上“开始本机配对”。
2. 本机配对时可开启引导小窗，前往“设置 → 隐私与安全性 → 开发者模式 → 与 Pawster 配对”；收到 PIN 后在系统页面输入。没有 PIN 时，小窗显示等待，不显示示例码。
3. 返回 App，“自动查询并只读验证路径”。此阶段不修改 PosterBoard 的文件；授权机制会使用本工具专用 App Group 的临时 Caches 链接。
4. 导入并选择 `.tendies`，检查注入计划，再确认注入。
5. 文件校验完成后，到系统壁纸界面检查；如需刷新注册，在“记录”中单独执行“备份并刷新注册”。本工具不自动重启手机或清空壁纸。
6. 若不需要本次内容，使用对应记录的“撤回这次注入”。有外部修改时会停止，保留现场。

## 架构

- `App/PairingService.swift`：配对生命周期、配对文件及查询入口。
- `App/PairingGuide.swift`：画中画引导和应用内回退。
- `App/AccessBroker.swift`：双引擎作用域及身份诊断；非负句柄（含 0）均按作用域释放。
- `App/WallpaperRepository.swift`：导入、结构分析、资源引用和内容哈希。
- `App/InjectionService.swift`：计划、提交、恢复、注册备份合并。
- `Core/src/network.rs`：从 AirCard-iOS 提取的连接和 InstallationProxy 查询代码，不包含 AirTraffic 注入流程。
- `Core/src/pairing.rs` / `operations.rs`：配对协议与取消、超时控制。
- `Core/src/archive.rs`：有大小限制的 ZIP 提取，拒绝越界路径、符号链接和名称冲突。

## 当前边界

只支持首版系统表及 Collections `.tendies`。不推断未注册的存储版本，不创建缺失的系统提供组件目录；多个可用存储版本并存时停止。保持包内现有标识意味着内部标识相同的不同包仍可能冲突；系统注册可见性必须实测。

画中画不代替用户操作“设置”，也不会识别用户当前所在设置页面。公开设置跳转仅打开本 App 的设置页。配对期间会开启静音音频保活，结束或超时后停止；这是需要真机验证的侧载工具行为。

仓库采用 GPL-3.0-or-later，保留第三方原有声明。上游版本及授权信息见 [第三方来源](ThirdParty/SOURCES.md)。
