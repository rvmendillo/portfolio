# ReyWidgets Studio

A native iPhone and iPad app for creating Home Screen widgets with SwiftUI layouts, HTML/CSS/JavaScript, custom JSON APIs, and on-device AI.

**Build status:** [iPhone and simulator builds passed, along with all 12 tests](https://github.com/rvmendillo/portfolio/actions/runs/34700075060). [Download the unsigned IPA](https://github.com/rvmendillo/portfolio/actions/runs/34700075060/artifacts/10299842657) from the build artifact ZIP. See `Docs/VALIDATION.md` for evidence and remaining device checks. Sign the app and extension before installing on an iPhone; model weights are separate.

## Included

- A SwiftUI studio with a collection, template gallery, designer, code workspace, API inspector, AI draft review, and settings.
- A real WidgetKit extension with individually selectable designs in small, medium, and large sizes.
- Native metric, clock, list, and progress layouts; customizable colors, SF Symbols, text, and JSON Pointer bindings. Medium and large API widgets include an App Intent refresh button.
- HTML/CSS/JavaScript editing and isolated WebKit previews. Publishing captures all three widget sizes before changing the published revision.
- On-device Apple Foundation Models where available, plus an actual llama.cpp GGUF runtime with Metal or CPU inference. No cloud fallback or simulated generation.
- Configurable HTTPS GET and read-only POST APIs, Keychain-stored headers, response inspection, sample JSON, bounded responses, refresh intervals, and cached-data fallback for native widgets.
- Import/export as `.reywidget.json`, duplication, deletion, widget-to-editor deep links, six editable templates, and an in-app guide.
- An included Xcode project, deterministic project generator, simulator build/test script, XCTest coverage, UI smoke tests, and a GitHub Actions workflow.

## Build and install

1. On a Mac, install **Xcode 26 or newer** with an iOS simulator/runtime and CMake (`brew install cmake`). Run `bash Scripts/prepare_runtime.sh` once, then open `ReyWidgets.xcodeproj`. The script builds the pinned llama.cpp source for iPhone and simulator; the app deployment target is iOS 17.0. If Xcode reports a missing Metal compiler, install it with `xcodebuild -downloadComponent MetalToolchain`. Model weights are separate.
2. Edit `Config/Base.xcconfig`. Set your unique `BUNDLE_ID_PREFIX` and `DEVELOPMENT_TEAM`. Keep `APP_GROUP` and `KEYCHAIN_GROUP` shared across both targets.
3. For the **ReyWidgets** and **ReyWidgetsExtension** targets, check Signing & Capabilities. Enable the same App Group and Keychain sharing group. Register the group in your Apple Developer account if needed. Use a signing team that supports these capabilities.
4. Choose the **ReyWidgets** scheme and run on your iPhone. Launch the app once. If shared storage is unavailable, the app shows the signing problem instead of silently saving somewhere the widget cannot read.
5. Open a template, run its preview, and tap **Publish**. On the Home Screen, hold an empty area → Edit → Add Widget (or + on older iOS) → ReyWidgets. Add the size you want, then hold the widget → Edit Widget → Design.

Command-line build and tests on macOS:

```sh
bash Scripts/build.sh build
bash Scripts/build.sh test
# Optional simulator override:
RW_DESTINATION='platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' bash Scripts/build.sh test
```

The test script chooses the newest installed iPhone simulator and sets test time limits. Avoid the iOS 18.5 simulator's [upstream WebKit loader issue](https://bugs.webkit.org/show_bug.cgi?id=293831); use a newer runtime for validation.

After configuring a signing team, create an archive with `bash Scripts/build.sh archive`, then export from Xcode Organizer with the appropriate signing method. The app and embedded `.appex` must both retain their App Group and Keychain entitlements. An unsigned ZIP renamed to `.ipa` will not provide working Home Screen widgets. A hosted app inside LiveContainer does not register its own system widget extension.

In `rvmendillo/portfolio`, `.github/workflows/build-reywidgets-ios.yml` selects Xcode 26+, builds and caches both AI runtime variants, builds the app and widget extension, packages an unsigned IPA, and runs simulator tests. Pushes to the ReyWidgets branch trigger this workflow. Check its result before using an artifact.

## Local AI

| Engine | Requirements | Setup |
| --- | --- | --- |
| Apple on-device model | iOS 26+, compatible Apple Intelligence hardware, model available and enabled | Choose it when Settings reports Ready |
| Imported GGUF | iOS 17+, sufficient free RAM/storage for the selected architecture and quantization | Import a single instruction-tuned `.gguf` file below 2 GB from Files |

For a phone without Apple Intelligence, such as an iPhone 13, use the GGUF route. Start with a small 0.5B–1.5B Q4 instruction model with an embedded chat template. The importer checks the file header and size; llama.cpp validates model compatibility at load time. The runtime reports unsupported models or allocation failures. Device-specific speed and memory limits are not yet measured.

Model weights are **not bundled** and must be obtained separately under their license. Once imported, generation needs no network, API key, or JIT. The runtime is built from llama.cpp **b10809**, pinned to commit `5266f24da75dc449bd56cbed7addb9c8e4a6a73e`. Building from source supplies both iPhone and simulator variants, which the published b10809 binary does not include. It loads for generation and unloads afterward; concurrency is serialized, output is capped, and cancellation is checked between decoding steps. The Apple model path checks actual availability before generating.

AI returns editable HTML/CSS/JavaScript. Review → Apply to editor → Run preview → Publish. Malformed or truncated results produce an error; they are not silently replaced with a canned template. Small local models may require shorter prompts and manual edits. API credentials and API response bodies are never automatically included in the AI prompt.

## What runs on the Home Screen

| Capability | Native widget | HTML widget |
| --- | --- | --- |
| Rendering | SwiftUI layout from the saved design | Published PNG snapshot from the in-app WebKit canvas |
| Editable on the phone | Visual controls and native layout JSON | HTML, CSS, JavaScript |
| API refresh | WidgetKit timeline; iOS controls scheduling | Fetch and render while publishing in the app |
| Interaction | Open the editor; API refresh on medium/large widgets | Tap to open the editor |
| Arbitrary JavaScript / animation | Not used by the native layout | Runs in the in-app preview, not on the Home Screen |

WidgetKit does not host a live `WKWebView`. HTML snapshots do not update when the app is closed and do not have independently tappable HTML buttons. Native API refresh intervals are requests, not real-time guarantees. Widget sizes vary by device; HTML presets are 170×170, 364×170 and 364×382 points and are scaled into the actual widget bounds. Full-color image appearance may be altered by the user's Home Screen tint setting.

The in-app native JSON language configures the four implemented layouts. To add new SwiftUI components or arbitrary Swift code, edit the source and rebuild in Xcode. This app does not pretend to compile downloaded Swift on the iPhone.

## APIs and customization

See `Docs/CUSTOMIZATION.md` for bindings, the HTML runtime contract, headers, and examples. One JSON endpoint is configured per widget. An aggregator endpoint can combine several sources.

The weather templates use an Open-Meteo URL with sample Manila data and networking **off** initially. Enable it yourself after reviewing the endpoint. The savings figure is explicitly sample data and is not connected to Maya or another bank.

Exports include URLs, request bodies, sample data, and source code, but omit stored headers and snapshot images. Inspect these fields before sharing. Imports receive a new identity and have networking turned off until you review the request. Duplicates also start without copied credentials.

## Source map

| Directory | Purpose |
| --- | --- |
| `App/` | SwiftUI studio, WebKit preview/capture, AI orchestration, GGUF engine |
| `Core/` | Shared models, storage, binding resolver, native renderer, API client, refresh intent |
| `Widget/` | WidgetKit provider, App Entity configuration and extension entry point |
| `Packages/LlamaRuntime/` | Swift Package for the locally built, revision-pinned runtime |
| `Config/` | Build settings, app/extension plists and shared entitlements |
| `Tests/`, `UITests/` | Native test suites to run on a Mac |
| `Scripts/` | Project generator, build script, desktop/static validation |
| `Examples/` | Editable HTML examples extracted from the actual app source |

To add or remove Swift files, run `python3 Scripts/generate_project.py` and reopen Xcode. The project is generated using only Python's standard library.

## Platform references

- [Apple: WidgetKit](https://developer.apple.com/documentation/widgetkit/)
- [Apple: Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Apple: Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Apple: Generating content with Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
- [llama.cpp: iPhone example](https://github.com/ggml-org/llama.cpp/tree/b10809/examples/llama.swiftui)
- [llama.cpp: pinned runtime release](https://github.com/ggml-org/llama.cpp/releases/tag/b10809)
