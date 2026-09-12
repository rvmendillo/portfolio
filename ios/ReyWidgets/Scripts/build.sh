#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
  echo "Xcode 26 or newer on macOS is required. Open ReyWidgets.xcodeproj after installing Xcode."
  exit 1
fi
rw_xcode_major="$(xcodebuild -version | awk '/^Xcode/{split($2,v,".");print v[1]}')"
if [[ "$rw_xcode_major" -lt 26 ]]; then
  echo "Select Xcode 26+ with xcode-select or DEVELOPER_DIR to compile FoundationModels."
  exit 1
fi
rw_action="${1:-build}"
bash Scripts/prepare_runtime.sh
case "$rw_action" in
  build)
    xcodebuild -project ReyWidgets.xcodeproj -scheme ReyWidgets -configuration Debug \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
      CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-" build
    ;;
  test)
    rw_destination="${RW_DESTINATION:-}"
    if [[ -z "$rw_destination" ]]; then
      # simctl lists older runtimes first. Prefer the newest installed iOS;
      # iOS 18.5 has a known libswiftWebKit loader bug for older deployment targets.
      rw_device_id="$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
runtimes = sorted((key for key in devices if "iOS-" in key),
                  key=lambda key: tuple(map(int, re.findall(r"\d+", key))), reverse=True)
for runtime in runtimes:
    phones = [device for device in devices[runtime] if "iPhone" in device["name"]]
    if phones:
        print("Testing on " + runtime + " / " + phones[0]["name"], file=sys.stderr)
        print(phones[0]["udid"])
        break
else:
    raise SystemExit("Install an iOS simulator runtime in Xcode before testing.")
')"
      xcrun simctl bootstatus "$rw_device_id" -b
      rw_destination="platform=iOS Simulator,id=$rw_device_id"
    fi
    xcodebuild -project ReyWidgets.xcodeproj -scheme ReyWidgets -configuration Debug \
      -destination "$rw_destination" -derivedDataPath build/DerivedData \
      -resultBundlePath "build/TestResults-$(date +%s).xcresult" \
      -parallel-testing-enabled NO -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 \
      CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-" test
    ;;
  archive)
    xcodebuild -project ReyWidgets.xcodeproj -scheme ReyWidgets -configuration Release \
      -destination 'generic/platform=iOS' -archivePath build/ReyWidgets.xcarchive \
      -allowProvisioningUpdates archive
    echo "Archive created. Use Xcode Organizer to export a signed IPA with your provisioning profiles."
    ;;
  *) echo "Usage: Scripts/build.sh [build|test|archive]"; exit 2 ;;
esac
