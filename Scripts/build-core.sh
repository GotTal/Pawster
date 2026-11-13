#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Requires macOS and Xcode.' >&2; exit 1; }
command -v cargo >/dev/null
xcrun --sdk iphoneos --show-sdk-path >/dev/null
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
for target in aarch64-apple-ios aarch64-apple-ios-sim; do
  if [[ "$target" == aarch64-apple-ios ]]; then sdk=iphoneos; else sdk=iphonesimulator; fi
  SDKROOT="$(xcrun --sdk "$sdk" --show-sdk-path)" IPHONEOS_DEPLOYMENT_TARGET=17.0 \
    cargo build --locked --manifest-path Core/Cargo.toml --release --features device --target "$target"
done
mkdir -p Frameworks
# Never remove an existing framework tree. Xcode writes to a fresh temporary destination.
staging="$(mktemp -d "${TMPDIR:-/tmp}/posterbridge-framework.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
xcodebuild -create-xcframework \
  -library Core/target/aarch64-apple-ios/release/libposterbridge_core.a -headers Core/include \
  -library Core/target/aarch64-apple-ios-sim/release/libposterbridge_core.a -headers Core/include \
  -output "$staging/PawsterCore.xcframework"
if [[ -e Frameworks/PawsterCore.xcframework ]]; then
  mv Frameworks/PawsterCore.xcframework "Frameworks/PawsterCore.previous.$(date +%s).xcframework"
fi
mv "$staging/PawsterCore.xcframework" Frameworks/PawsterCore.xcframework
echo 'Core framework built.'
