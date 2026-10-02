#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# b10809's published XCFramework omits the iOS simulator. Build both variants
# from the exact upstream source revision using its own XCFramework builder.
rw_revision="5266f24da75dc449bd56cbed7addb9c8e4a6a73e"
rw_frameworks="$PWD/Packages/LlamaRuntime/Frameworks"
rw_source="$PWD/build/llama-source"
rw_stamp="$rw_frameworks/build-version.txt"
rw_version="$rw_revision $(xcodebuild -version | tr '\n' ' ')"

if [[ -f "$rw_stamp" && "$(cat "$rw_stamp")" == "$rw_version" && -f "$rw_frameworks/llama.xcframework/Info.plist" ]]; then
  echo "Using prepared llama.cpp iPhone and simulator framework."
  exit 0
fi
for rw_tool in git cmake xcrun python3; do
  if ! command -v "$rw_tool" >/dev/null; then
    echo "Missing $rw_tool. Install Xcode 26+ and CMake (brew install cmake)."
    exit 1
  fi
done

mkdir -p "$rw_source" "$rw_frameworks"
git -C "$rw_source" init --quiet
if ! git -C "$rw_source" remote get-url origin >/dev/null 2>&1; then
  git -C "$rw_source" remote add origin https://github.com/ggml-org/llama.cpp.git
fi
git -C "$rw_source" fetch --depth 1 origin "$rw_revision"
git -C "$rw_source" checkout --detach "$rw_revision"
test "$(git -C "$rw_source" rev-parse HEAD)" == "$rw_revision"
(
  cd "$rw_source"
  bash build-xcframework.sh ios-device ios-sim
)
python3 - "$rw_source/build-apple/llama.xcframework/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as handle:
    libraries = plistlib.load(handle)['AvailableLibraries']
variants = {(lib['SupportedPlatform'], lib.get('SupportedPlatformVariant', 'device')) for lib in libraries}
if not {('ios', 'device'), ('ios', 'simulator')} <= variants:
    raise SystemExit('The runtime must include iOS device and simulator libraries.')
print('Validated runtime platforms:', sorted(variants))
PY
# Replace only this generated dependency, after a successful complete build.
rm -rf "$rw_frameworks/llama.xcframework"
cp -R "$rw_source/build-apple/llama.xcframework" "$rw_frameworks/"
printf '%s\n' "$rw_version" > "$rw_stamp"
