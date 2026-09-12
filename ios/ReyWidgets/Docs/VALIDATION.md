# Validation record

Updated 12 September 2026. GitHub Actions builds this project with Xcode 26.3. It is **not a device-certified or signed release**.

Verified build: [GitHub Actions run 34700075060](https://github.com/rvmendillo/portfolio/actions/runs/34700075060) on commit `7807f7218eeb3bfb2c2fd5b8cea52670ecf09457`. **iPhone build, simulator build, and all 12 tests passed.** The test device was iPhone 17 Pro / iOS 26.2. Detailed results are in `CheckResults/native-results.json`.

[Download the unsigned IPA artifact](https://github.com/rvmendillo/portfolio/actions/runs/34700075060/artifacts/10299842657) (ZIP containing `ReyWidgets-unsigned.ipa`).

## Checks actually completed

| Check | Result |
| --- | --- |
| Xcode builds | App and embedded WidgetKit extension compiled and linked for iPhone Release and simulator Debug using Xcode 26.3. |
| Core and WebKit tests | 10 passed, 0 failed. Actual WebKit captures have the expected dimensions and final pixel color after asynchronous JavaScript at all three sizes. |
| UI tests | 2 passed, 0 failed. Created a native widget and opened its editor; discovered Settings and the GGUF import control. No shared-storage alert appeared with local simulator signing. |
| IPA package | ZIP integrity passed. The package contains the app executable, embedded widget extension, and llama framework. It is unsigned. |
| Swift source parsing, including tests and package manifest | 17 files parsed with tree-sitter Swift; no syntax errors. This is not Swift type checking. |
| Xcode project OpenStep parsing | Parsed successfully: 102 objects, 139 checked object references, no unresolved references. |
| Project configuration | Four targets, shared scheme, extension embedded in the app, and local Swift Package reference present. |
| App and widget storage entitlements | Matching App Group and Keychain sharing values; generated property lists parsed. |
| llama.cpp dependency | Built from b10809 source commit `5266f24da75dc449bd56cbed7addb9c8e4a6a73e` with both iPhone and simulator libraries. Both variants compile and link in GitHub Actions. |
| Shell script syntax | `bash -n Scripts/build.sh Scripts/prepare_runtime.sh` passed. |
| HTML runtime JavaScript | Both actual templates at all three sizes executed in Node.js with a DOM test double. All six combinations passed script and data-binding checks. |
| Runtime data cases | Verified missing/null fallback, false and zero preservation, Unicode, escaped JSON Pointer segments, size metadata, and rejection of inherited properties. |
| Preview harness | JavaScript parsed successfully; CSP directives checked as source. Enforcement and visual rendering were not verified. |

Run the portable checks from the project directory:

```sh
python3 -m pip install tree-sitter tree-sitter-swift
python3 Scripts/validate.py
node Scripts/check_runtime.cjs
```

The generated fixtures come directly from `Core/Templates.swift` and `App/HTMLRuntime.swift`. `Docs/HTML-Preview.html` contains the six previews and a browser test harness. Its PASS labels are produced only when its checks actually run in a browser.

## Checks not performed

- **Physical-device Home Screen installation, App Group provisioning, shared Keychain access, WidgetKit scheduling, or App Intent execution.** These require a properly signed device build. The app reports shared-storage failures instead of hiding them.
- **Full visual review.** The real iOS WebKit capture test verifies all three output sizes and the final pixel color after asynchronous JavaScript. Detailed template layout review, Dynamic Type, VoiceOver, and Home Screen tint still need interactive testing. The standalone desktop preview harness was not visually inspected.
- **Apple model or GGUF generation on an iPhone.** No device or model weights were available. The implemented inference path, runtime API use, cancellation points, bounds and error handling were reviewed, but output quality, generation speed and memory behavior need device testing.
- **Live external API requests or authentication.** Sample JSON and runtime bindings were exercised. Actual endpoint reachability, account credentials and server response behavior were not tested.
- **Device signing.** GitHub Actions packages an unsigned IPA with the app, widget extension, and AI framework. Installing it requires signing both app and extension with the matching shared capabilities.

## Required Mac/device acceptance pass

1. Run `bash Scripts/prepare_runtime.sh` before opening Xcode, or use `bash Scripts/build.sh test`, which prepares the runtime automatically.
2. Verify both targets' App Group and Keychain capabilities on your development team; install and launch on the device.
3. Publish native and HTML designs. Add each size from the Home Screen gallery and select different designs on separate widget instances.
4. Verify that edits, deletion, and deep links select the expected design. For HTML, confirm all three sizes render before the published revision changes.
5. Connect a known read-only JSON API with a test credential. Exercise success, offline fallback, changed credentials, 401, redirects, timeout, and oversized JSON. Confirm no header values appear in project exports.
6. Test a small instruction GGUF on the oldest supported target phone, with Metal enabled and disabled. Generate, cancel, import another model, and retry after a load failure. Verify the Apple route's availability gate on compatible and incompatible devices.
7. Check long titles, large Dynamic Type, VoiceOver, iPad layout, Home Screen tint, widget memory use and repeated snapshot publishing.

The 10 core tests cover parsing/bindings, request URL validation, import/export boundaries, cache invalidation, invalid documents, template round trips, AI-output parsing, encoded API injection boundaries, and real WebKit snapshot rendering. The two UI tests cover widget creation and local-model settings discovery.
