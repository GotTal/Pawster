# Maintainer Notes / 维护说明

## Pull requests and checks

`Repository checks` runs documentation/form validation, localization checks and Python tests. `Build and test Pawster` always reports `iOS validation` for a PR; its scope job decides whether native tests are needed. App, Core, Tests and native build-script changes require native validation. Native workflow/scope changes are validated on PR as well. A docs-only change produces a successful validation gate without starting a Mac runner. Failures and cancellations do not satisfy the gate.

PR jobs use a read-only token, have no release private key and never package an IPA. Fork workflows may require maintainer approval. Do not use `pull_request_target` to execute contributor-controlled builds.

Require the `Repository checks` and `iOS validation` check contexts on main, originating from GitHub Actions. Require a PR and resolved review conversations; zero required approvals supports one-maintainer operation. Resolve discussion feedback before merging. A maintainer exception, if needed, is limited to PRs so direct force pushes and branch deletion remain blocked. Do not bypass a failed check as a routine merge step.

`Scripts/ci-scope.py` routes changes and has regression tests. When adding build-relevant paths, update its classification and tests. Generated projects and frameworks stay outside version control. Build/toolchain changes are not verified merely by YAML parsing; run a PR with the real workflow.

## Test packages and publication

A native change pushed to main or `testing/**` may package an IPA. Test-only changes run native validation but packaging can be requested explicitly when needed. A documentation/workflow-only main push does not package. For manual validation use workflow dispatch; set `package_ipa` false to validate without producing an IPA. With packaging enabled, a main dispatch uses the release channel; other refs use test identity. This creates an Actions artifact, not a published Release.

Official publication needs an explicit maintainer decision and its own version/tag/build consistency check. Keep the [README](../README.md) install links on `/releases/latest`; filenames containing a version should be selected from that page. Release attachments remain versioned, avoiding mutable aliases and signatures that refer to a different filename.

Follow [release verification](VERIFYING_RELEASES.md) for key custody, pinned certificate identity, checksum manifests and detached signatures. Keep source archives, IPA and provenance bound to the successful commit. Never move an existing release tag or silently replace a release identity. The current signing tool refuses to overwrite a signed staging directory.

## Community and evidence

Keep labels used by issue forms available, including `localization` and `compatibility`. Newcomer tasks should have a narrow scope, clear file pointers and an achievable completion condition. Maintain the [compatibility table](COMPATIBILITY.md) using linked device reports; keep untested combinations marked accordingly. Use the [FAQ](FAQ.md) for recurring setup questions.

Third-party authorization gaps remain tracked in [source notes](../ThirdParty/SOURCES.md). No community document clears them. New dependencies and contributed fixtures need source and license information. Private security and conduct reports use the published email; do not promise deadlines the project cannot maintain.

## 仓库设置与发布约定

main 的必需检查为 `Repository checks` 和 `iOS validation`，先确认检查确实运行，再启用规则。要求 PR 与讨论已解决；单人维护阶段不设置第二人的强制审批。维护者例外仅通过 PR 使用，不作为日常跳过失败检查的办法。

纯文档改动只跑轻量检查；原生工作流修改会在 PR 上实际验证；原生代码或构建改动才在推送时打包，测试文件单独修改可手动请求包。手动触发时可关闭 `package_ipa`。任何 Actions 包均不自动代表正式发布；发布仍需维护者明确决定。

README 安装入口固定指向 latest，具体版本附件保持原名并通过同版签名清单验证。实机兼容性、第三方授权、密钥恢复与正式发布验证分别记录，不将自动化通过视作全部验收。
