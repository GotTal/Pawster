# Contributing to Pawster 🐾

**English** · [简体中文](CONTRIBUTING_CN.md)

Thanks for lending a paw. Translations, documentation, reproducible bug reports and focused code changes are welcome.

## Choose a task

Check [open issues](https://github.com/GotTal/Pawster/issues) before starting. Small improvements can go straight to a pull request; discuss new engines, broader system support, credential handling or changes to wallpaper storage in an issue first. The labels `good first issue` and `help wanted` identify suitable tasks.

## Development setup

- Use an Apple silicon Mac, Xcode with an iOS 26-or-later SDK, Rust stable and XcodeGen. The published 0.2.0 build used Xcode 26.6; newer tools need their own validation.
- Fork the repository and create a focused branch from current `main`. Branch names such as `fix/pairing-status`, `docs/setup` or `l10n/zh-Hant` are welcome; a maintainer may use `testing/**` for device builds.
- `project.yml` is the source of the Xcode project. Do not commit generated Xcode projects, frameworks or build output.

```sh
git clone https://github.com/YOUR-USERNAME/Pawster.git
cd Pawster
git remote add upstream https://github.com/GotTal/Pawster.git
git switch -c fix/your-change
brew install xcodegen
bash Scripts/build-core.sh
xcodegen generate
```

See the [architecture](Docs/ARCHITECTURE.md) for source ownership and the [README](README.md#building-from-source) for packaging. Windows and Linux can be used for documentation, language-pack and repository checks; Xcode builds require macOS. Contributors without a Mac can use the PR checks or the workflow in their own fork.

## Validate the change

```sh
python3 -m venv .venv
# Windows: .venv\Scripts\activate
. .venv/bin/activate
python -m pip install -r Scripts/requirements-checks.txt
python Scripts/check-community.py
python Scripts/check-localizations.py
python -m unittest discover -s Scripts/tests -v
```

For app/core changes, also run on macOS:

```sh
cargo test --locked --manifest-path Core/Cargo.toml --features device
xcrun simctl list devices available
TEST_DESTINATION='platform=iOS Simulator,id=SIMULATOR_UDID' bash Scripts/test-macos.sh
```

Replace the simulator identifier with one available locally. For device behavior, follow the [device checklist](Docs/实机验证步骤.md) and record what was actually exercised. Simulator tests do not establish pairing trust, PiP behavior in Settings, wallpaper registration or NeoSpring effects on a phone.

## Submit a pull request

Target `main` unless a maintainer has requested a different base. Explain the problem, final behavior and checks performed. Include screenshots for visible changes, with pairing codes, identifiers and personal content removed. Keep unrelated formatting and dependency updates separate.

Every PR gets repository checks and an iOS validation result. Native builds run when app/core/build logic changes; documentation-only changes use the lightweight checks. PRs do not package IPAs or access release keys. A first contribution from a fork may need a maintainer to approve the workflow. `main` requires passing checks and resolved review conversations; one-person maintenance does not require a second person's approval. Maintainer rule exceptions are limited to pull requests.

Use the [Build and test Pawster workflow](https://github.com/GotTal/Pawster/actions/workflows/build.yml) to request a test IPA when needed. A native-code push to `testing/**` can also produce one. Test packages share the production app identifier and replace an existing Pawster installation. Official tags, signatures and Releases are managed by GotTal; a merged PR does not authorize publication of a new release.

## Code, translations and third-party changes

Follow the surrounding Swift and Rust style. Keep blocking work off the main thread, release scoped file-access handles on all paths, and preserve cancellation and transaction boundaries. Tests should cover changed behavior and meaningful failure cases. Keep user-facing strings in language packs; use the [localization guide](Docs/LOCALIZATION.md) for locale mapping and fallbacks.

Start device verification with read-only operations. Preserve existing wallpapers and receipts; discuss destructive operations separately. Do not commit real pairing files, live PINs, signing keys or private wallpaper packs. Use synthetic fixtures or content with clear permission to redistribute.

Keep third-party notices and pinned provenance. Pawster's own code uses GPL-3.0-or-later; upstream components retain their own terms. Review [source notes](ThirdParty/SOURCES.md) before importing or changing third-party code, including the existing unresolved authorization items. State the source and license of new dependencies.

## Communication

Be patient and specific, and follow the [code of conduct](CODE_OF_CONDUCT.md). General questions belong in Issues using the question link, or in [Discussions](https://github.com/GotTal/Pawster/discussions) if enabled. Report vulnerabilities privately using [SECURITY.md](SECURITY.md). The maintainer does not promise a fixed review or support turnaround.
