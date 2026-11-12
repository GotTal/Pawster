#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen before building.' >&2; exit 1; }
[[ -d Frameworks/PawsterCore.xcframework ]] || bash Scripts/build-core.sh
channel="${PAWSTER_BUILD_CHANNEL:-test}"
case "$channel" in
  test|release) ;;
  *) echo 'PAWSTER_BUILD_CHANNEL must be test or release.' >&2; exit 1 ;;
esac
if [[ "$channel" == release && "${GITHUB_ACTIONS:-false}" == true && "${GITHUB_REF:-}" != refs/heads/main ]]; then
  echo 'Release packages may only be built from main in CI.' >&2; exit 1
fi
build_settings=("CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO")
if [[ -n "${PAWSTER_BUILD_NUMBER:-}" ]]; then
  [[ "$PAWSTER_BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo 'Invalid build number.' >&2; exit 1; }
  build_settings+=("CURRENT_PROJECT_VERSION=$PAWSTER_BUILD_NUMBER")
fi
xcodegen generate
xcodebuild -project Pawster.xcodeproj -scheme Pawster -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  "${build_settings[@]}" build
mkdir -p build/Packages
package="$(mktemp -d "${TMPDIR:-/tmp}/posterbridge-ipa.XXXXXX")"
trap 'rm -rf "$package"' EXIT
mkdir "$package/Payload"
cp -R build/DerivedData/Build/Products/Release-iphoneos/Pawster.app "$package/Payload/"
app="$package/Payload/Pawster.app"
suffix=""
if [[ "$channel" == test ]]; then
  revision="$(git rev-parse --short=7 HEAD)"
  suffix="-test.${PAWSTER_BUILD_NUMBER:-local}-$revision"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Pawster Test' "$app/Info.plist"
  # Localized names override Info.plist. Keep the test identity in every localization.
  for localized_info in "$app"/*.lproj/InfoPlist.strings; do
    [[ -f "$localized_info" ]] || continue
    localized_test_name="$(/usr/libexec/PlistBuddy -c 'Print :PawsterTestDisplayName' "$localized_info" 2>/dev/null || printf '%s' 'Pawster Test')"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $localized_test_name" "$localized_info"
  done
fi
/usr/libexec/PlistBuddy -c "Add :PawsterBuildChannel string $channel" "$app/Info.plist"
/usr/libexec/PlistBuddy -c "Add :PawsterSourceRevision string $(git rev-parse HEAD)" "$app/Info.plist"
# Ad-hoc entitlement embedding preserves the App Group for sideload signers to rewrite.
codesign --force --sign - --entitlements App/Pawster.entitlements "$package/Payload/Pawster.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$package/Payload/Pawster.app/Info.plist")"
artifact_name="Pawster-$version$suffix"
out="$(pwd)/build/Packages/$artifact_name.ipa"
ditto -c -k --keepParent "$package/Payload" "$out"
echo "$out"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "artifact_name=$artifact_name" >> "$GITHUB_OUTPUT"
fi
