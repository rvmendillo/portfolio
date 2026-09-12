# Validation record

Prepared 12 September 2026. This is an implemented source handoff, **not a device-certified or signed release**.

## Checks actually completed

| Check | Result |
| --- | --- |
| Swift source parsing, including tests and package manifest | 17 files parsed with tree-sitter Swift; no syntax errors. This is not Swift type checking. |
| Xcode project OpenStep parsing | Parsed successfully: 102 objects, 139 checked object references, no unresolved references. |
| Project configuration | Four targets, shared scheme, extension embedded in the app, and local Swift Package reference present. |
| App and widget storage entitlements | Matching App Group and Keychain sharing values; generated property lists parsed. |
| llama.cpp dependency | b10809 XCFramework URL and SHA-256 pinned from the upstream release; upstream iOS minimum is 16.4, below this app's 17.0 deployment target. Binary resolution/linking was not executed here. |
| Shell script syntax | `bash -n Scripts/build.sh` passed. |
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

- **Xcode build/type checking, simulator execution, and native XCTest/UI tests.** This environment is Linux and has no Apple SDK or Xcode. Build scripts and tests are included for a Mac.
- **Actual Home Screen installation, App Group provisioning, shared Keychain access, WidgetKit scheduling, or App Intent execution.** These require a properly signed device build. The app reports shared-storage failures instead of hiding them.
- **WebKit snapshot quality and behavior on iOS.** Desktop visual inspection also remains unverified: the available browser's policy blocked opening local preview files. A standalone browser executable could not be downloaded. No rendering pass or screenshot is claimed.
- **Apple model or GGUF generation on an iPhone.** No device or model weights were available. The implemented inference path, runtime API use, cancellation points, bounds and error handling were reviewed, but output quality, generation speed and memory behavior need device testing.
- **Live external API requests or authentication.** Sample JSON and runtime bindings were exercised. Actual endpoint reachability, account credentials and server response behavior were not tested.
- **Signing or IPA packaging.** No installable IPA is included.

## Required Mac/device acceptance pass

1. Resolve the pinned Swift Package, build both app and extension, and run `Scripts/build.sh test`.
2. Verify both targets' App Group and Keychain capabilities on your development team; install and launch on the device.
3. Publish native and HTML designs. Add each size from the Home Screen gallery and select different designs on separate widget instances.
4. Verify that edits, deletion, and deep links select the expected design. For HTML, confirm all three sizes render before the published revision changes.
5. Connect a known read-only JSON API with a test credential. Exercise success, offline fallback, changed credentials, 401, redirects, timeout, and oversized JSON. Confirm no header values appear in project exports.
6. Test a small instruction GGUF on the oldest supported target phone, with Metal enabled and disabled. Generate, cancel, import another model, and retry after a load failure. Verify the Apple route's availability gate on compatible and incompatible devices.
7. Check long titles, large Dynamic Type, VoiceOver, iPad layout, Home Screen tint, widget memory use and repeated snapshot publishing.

The included native tests cover parsing/bindings, request URL validation, import/export boundaries, cache invalidation, invalid documents, template round trips, AI-output parsing, and encoded API injection boundaries. They are written but not claimed as executed.
