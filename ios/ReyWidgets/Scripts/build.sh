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
case "$rw_action" in
  build)
    xcodebuild -project ReyWidgets.xcodeproj -scheme ReyWidgets -configuration Debug \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
      CODE_SIGNING_ALLOWED=NO build
    ;;
  test)
    rw_destination="${RW_DESTINATION:-}"
    if [[ -z "$rw_destination" ]]; then
      rw_device_id="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for key,items in d["devices"].items() if "iOS" in key for v in items if "iPhone" in v["name"]))')"
      rw_destination="platform=iOS Simulator,id=$rw_device_id"
    fi
    xcodebuild -project ReyWidgets.xcodeproj -scheme ReyWidgets -configuration Debug \
      -destination "$rw_destination" -derivedDataPath build/DerivedData \
      -resultBundlePath "build/TestResults-$(date +%s).xcresult" CODE_SIGNING_ALLOWED=NO test
    ;;
  archive)
    xcodebuild -project ReyWidgets.xcodeproj -scheme ReyWidgets -configuration Release \
      -destination 'generic/platform=iOS' -archivePath build/ReyWidgets.xcarchive \
      -allowProvisioningUpdates archive
    echo "Archive created. Use Xcode Organizer to export a signed IPA with your provisioning profiles."
    ;;
  *) echo "Usage: Scripts/build.sh [build|test|archive]"; exit 2 ;;
esac
