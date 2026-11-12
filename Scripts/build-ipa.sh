#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen before building.' >&2; exit 1; }
[[ -d Frameworks/PawsterCore.xcframework ]] || bash Scripts/build-core.sh
xcodegen generate
xcodebuild -project Pawster.xcodeproj -scheme Pawster -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p build/Packages
package="$(mktemp -d "${TMPDIR:-/tmp}/posterbridge-ipa.XXXXXX")"
trap 'rm -rf "$package"' EXIT
mkdir "$package/Payload"
cp -R build/DerivedData/Build/Products/Release-iphoneos/Pawster.app "$package/Payload/"
# Ad-hoc entitlement embedding preserves the App Group for sideload signers to rewrite.
codesign --force --sign - --entitlements App/Pawster.entitlements "$package/Payload/Pawster.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$package/Payload/Pawster.app/Info.plist")"
out="$(pwd)/build/Packages/Pawster-$version.ipa"
ditto -c -k --keepParent "$package/Payload" "$out"
echo "$out"
