# 为喵贴贡献一份小爪力 🐾

[English](CONTRIBUTING.md) · **简体中文**

欢迎补充翻译、改进文档、反馈可复现的问题，或提交范围清楚的代码修改。

## 开始之前

先查看[现有 Issue](https://github.com/GotTal/Pawster/issues)。小改进可以直接提交 PR；新增访问引擎、扩大系统支持范围、调整凭据处理或系统壁纸存储方式，请先开 Issue 讨论。`good first issue` 与 `help wanted` 标签用于标记适合参与的任务。

## 开发环境

- 建议 Apple 芯片 Mac，安装含 iOS 26 或更新 SDK 的 Xcode、Rust stable 与 XcodeGen。0.2.0 使用 Xcode 26.6 构建，更新工具链需要另行验证。
- Fork 后从当前 `main` 创建独立分支，例如 `fix/pairing-status`、`docs/setup`、`l10n/zh-Hant`。维护者可使用 `testing/**` 提供实机测试包。
- Xcode 工程由 `project.yml` 生成；不要提交生成的工程、原生库或构建产物。

```sh
git clone https://github.com/YOUR-USERNAME/Pawster.git
cd Pawster
git remote add upstream https://github.com/GotTal/Pawster.git
git switch -c fix/your-change
brew install xcodegen
bash Scripts/build-core.sh
xcodegen generate
```

源码职责见[架构说明](Docs/ARCHITECTURE.md)，打包见[README](README_CN.md#从源码构建)。Windows/Linux 可以参与文档、本地化和仓库检查；Xcode 构建需要 macOS。没有 Mac 时，可以使用 PR 自动检查或自己 Fork 中的工作流。

## 验证修改

```sh
python3 -m venv .venv
# Windows：运行 .venv\Scripts\activate
. .venv/bin/activate
python -m pip install -r Scripts/requirements-checks.txt
python Scripts/check-community.py
python Scripts/check-localizations.py
python -m unittest discover -s Scripts/tests -v
```

涉及 App 或 Rust 核心时，还需在 macOS 运行：

```sh
cargo test --locked --manifest-path Core/Cargo.toml --features device
xcrun simctl list devices available
TEST_DESTINATION='platform=iOS Simulator,id=SIMULATOR_UDID' bash Scripts/test-macos.sh
```

将模拟器标识换为本机实际可用值。涉及实机行为时，按[实机验证步骤](Docs/实机验证步骤.md)记录真正测试过的内容。模拟器测试不能证明手机上的配对信任、跨 App 画中画、壁纸注册或 NeoSpring 效果。

## 提交 PR

除非维护者另有说明，目标分支选择 `main`。说明问题、最终行为和验证结果；界面改动附截图，并隐藏配对码、设备标识和个人内容。无关格式化与依赖更新请分开提交。

所有 PR 都有仓库检查和 iOS 验证结果；涉及 App、核心或原生构建流程时才启动完整原生验证，纯文档改动运行轻量检查。PR 不打包 IPA，也不访问发布私钥。首次从 Fork 提交时，可能需要维护者批准工作流。main 要求检查通过并解决审查讨论；只有一位维护者时，不设置第二人的强制审批。维护者规则例外仅允许通过 PR 使用。

需要实机包时，可运行 [Build and test Pawster](https://github.com/GotTal/Pawster/actions/workflows/build.yml) 工作流；向 `testing/**` 推送原生代码改动也可生成测试包。测试包与正式版使用相同应用标识，会覆盖安装。正式标签、文件签名与 Release 由 GotTal 管理；PR 合并不等于授权发布新版本。

## 代码、本地化与第三方内容

遵循现有 Swift/Rust 风格，避免主线程阻塞，确保文件访问句柄在所有分支释放，保留取消和事务边界。测试应覆盖变更行为及关键失败场景。界面文字写入语言包，地区映射与回落规则见[本地化规范](Docs/LOCALIZATION.md)。

实机验证从只读操作开始，保留原壁纸和操作记录；破坏性操作须单独讨论。不要提交真实配对文件、实时 PIN、签名私钥或私人壁纸包。测试内容使用合成数据或明确允许再分发的素材。

保留第三方署名与固定来源。喵贴自身代码采用 GPL-3.0-or-later，上游保留其许可。引入或修改第三方代码前查看[来源说明](ThirdParty/SOURCES.md)，其中已有待补证的授权事项。新增依赖需说明来源与许可。

## 沟通

请耐心、具体地沟通并遵守[行为准则](CODE_OF_CONDUCT.md)。普通问题可以通过 Issue 的提问入口反馈，讨论区启用后也可使用 [Discussions](https://github.com/GotTal/Pawster/discussions)。安全问题按 [SECURITY.md](SECURITY.md) 私下报告。维护者不承诺固定的审查或支持时限。
