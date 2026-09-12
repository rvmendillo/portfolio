# Rey Portfolio Native 2

SwiftUI/UIKit edition with a PDFKit resume viewer, persistent source editor, real embedded CPython, bundled local coding model, touch GUI Designer, local packages and portfolio screens. It does not load the website or use a web view.

## Build on macOS

Use Xcode with iOS 18 SDK or later, Python 3.11+ and XcodeGen. From the repository root:

```sh
python3 scripts/prepare-native.py
cd ios-native
xcodegen generate
xcodebuild -project ReyPortfolioNative.xcodeproj -scheme ReyPortfolioNative -sdk iphoneos -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

Dependency preparation verifies SHA-256 for CPython, llama.cpp and the 491,400,064-byte model. On macOS it builds the missing Simulator framework from the matching pinned llama.cpp source revision and combines it with the release's device slice. It preserves the model/runtime license notices. Allow space for weights, Python's standard library and framework slices during building/signing.

The target is iOS 18.0, covering iPhone 16 Plus. The bundle ID remains `com.reyvictor.portfolioos.native`. Device installation needs a signed build and matching provisioning profile. The native GitHub Actions workflow has successfully built an unsigned IPA. See the root `REIMPLEMENTATION.md` for the final run and acceptance evidence.

## Implementation

- `NativeIDE.swift`: native editing, syntax highlighting, symbol completions, find, file/project import/export, input/output, AI chat and reviewed edits.
- `DeveloperEngine.swift`: serial runtime queues, local model state and atomic workspace persistence.
- `RuntimeBridge.mm`: CPython C API and llama.cpp inference, token streaming, cancellation and Metal on device.
- `Resources/app/`: generated shared Python modules. Edit `shared/`, then run preparation/build.
- `DesignerCodec.swift`: YAML parsing and package validation.

Python is the executable language here. Other source can be edited/exported; it does not report fabricated execution. AI uses a compact Qwen coding model, not Apple Intelligence or cloud ChatGPT. No AI API key is needed.

## Required native checks

Run the `ReyPortfolioNative` XCTest scheme on Simulator. The native workflow runs tests before packaging: Python behavior/errors/budgets, compiler diagnostics, persistence, calculator overflow handling and actual bundled-model inference. UI tests open and close all 13 app screens, edit/run/reopen saved source, and generate/review/apply/run real model code, including Stop and Unload. They use the app's motion-off preference and bounded timeouts. The workflow exports screenshots and an XCTest result summary.

Then verify an installed iPhone build: model load and sustained generation, Stop, background/resume, file persistence/import/export, PDF display, designer connections/install/launch and memory recovery. Linux smoke tests do not verify Swift compilation, Metal, signing or iOS interaction.
