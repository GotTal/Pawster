#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Scripts/check-localizations.py
cargo test --locked --manifest-path Core/Cargo.toml --features device
[[ -d Frameworks/PawsterCore.xcframework ]] || bash Scripts/build-core.sh
xcodegen generate
destination="${TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
xcodebuild -project Pawster.xcodeproj -scheme Pawster -configuration Debug \
  -destination "$destination" -derivedDataPath build/TestData -resultBundlePath build/TestResults.xcresult CODE_SIGNING_ALLOWED=NO test
