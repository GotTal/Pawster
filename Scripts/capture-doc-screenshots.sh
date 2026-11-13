#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Only a disposable CI simulator is used. No real device or pairing operations.
[[ "${GITHUB_ACTIONS:-false}" == true ]] || { echo 'This capture helper is for the CI simulator only.' >&2; exit 1; }
simulator="${TEST_DESTINATION##*id=}"
[[ "$simulator" =~ ^[A-Fa-f0-9-]{36}$ ]] || { echo 'A simulator ID is required.' >&2; exit 1; }
bundle=io.github.gottal.wallpapers
app=build/TestData/Build/Products/Debug-iphonesimulator/Pawster.app
[[ -d "$app" ]] || { echo 'The simulator app must be built by the test step first.' >&2; exit 1; }
# XCTest may run in a cloned simulator and leave the selected base shut down.
# Boot the chosen CI simulator explicitly and install the exact tested build.
state="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["state"] for devices in d["devices"].values() for x in devices if x["udid"]==sys.argv[1]))' "$simulator")"
if [[ "$state" != Booted ]]; then xcrun simctl boot "$simulator"; fi
xcrun simctl bootstatus "$simulator" -b
xcrun simctl install "$simulator" "$app"
xcrun simctl get_app_container "$simulator" "$bundle" app >/dev/null
policy="$(python3 -c 'import re,pathlib; print(re.search(r"static let policyVersion = \"([^\"]+)\"", pathlib.Path("App/AppPreferences.swift").read_text()).group(1))')"
mkdir -p build/DocumentationScreenshots
xcrun simctl ui "$simulator" appearance light
xcrun simctl status_bar "$simulator" override --time '9:41' --batteryState charged --batteryLevel 100
trap 'xcrun simctl terminate "$simulator" "$bundle" >/dev/null 2>&1 || true; xcrun simctl status_bar "$simulator" clear >/dev/null 2>&1 || true' EXIT
for language in en zh-Hans; do
  if [[ "$language" == en ]]; then locale=en_US; else locale=zh_CN; fi
  for screen in wallpapers setup welcome; do
    consent="$policy"; deferred=YES
    if [[ "$screen" == welcome ]]; then consent=preview-not-accepted; fi
    if [[ "$screen" == setup ]]; then deferred=NO; fi
    xcrun simctl terminate "$simulator" "$bundle" >/dev/null 2>&1 || true
    xcrun simctl launch "$simulator" "$bundle" \
      -AppleLanguages "($language)" -AppleLocale "$locale" \
      -appearance light -animatedBackgroundEnabled NO -diagnosticLogLimit 0 \
      -acceptedPolicyVersion "$consent" -acknowledgedRiskPolicyVersion "$consent" \
      -setup.completed NO -setup.deferred "$deferred" -setup.step install
    sleep 3
    xcrun simctl io "$simulator" screenshot "build/DocumentationScreenshots/$language-$screen.png"
  done
done
