# Rey OS 2

Rey Victor Mendillo's portfolio desktop and separate SwiftUI iOS app. The developer tools now use real CPython execution and a local GGUF coding model.

## Run the web app

Requires Node.js 22+ and Python 3.11+.

```sh
npm ci
npm run build
python3 -m http.server 8765
```

Open `http://localhost:8765`. Serve the generated `assets/`, `index.html`, `styles.css`, `script.js`, `sw.js`, `manifest.webmanifest` and `icon.svg` through HTTPS or localhost. Opening an HTML file directly does not support workers or the model cache.

## Included behavior

- Move, resize, minimize, restore, maximize and close desktop windows; phone dragging; Windows, iOS and resume themes; per-profile preferences.
- About, PDF resume, Projects, searchable File Explorer with document downloads and history, Browser, Calculator, Settings and App Studio.
- IDE with CodeMirror syntax editing, completions, find, undo, project files, import/export, local saves, stdin, real Python and JavaScript output/errors, Stop and a local AI panel.
- Real streamed local inference, load/import/unload, cancellation, optional current-file context and proposed replacements that require review and reject stale edits.
- GUI Designer controls, bindings, preview, editable YAML, framework source export and locally installed designs.
- Python AST conversion to Java/C++, plus existing English/Filipino HumanCode and GUI exporters.
- PWA app-file caching. Python assets cache after first use; model weights use the inference library's browser cache.

The separate `ios-native/` app uses SwiftUI/UIKit, PDFKit, embedded CPython and llama.cpp. See `ios-native/README.md` for its build instructions.

## Local model

The default is **Qwen2.5 Coder 0.5B Instruct, Q4_K_M**. Its exact revision, URL and SHA-256 are in `shared/model.json`. It is a small mobile coding model, not a claim to the newest or most capable coding model.

The web app downloads about 469 MiB on first load. It supports importing a compatible GGUF below 1.6 GB; browser memory can impose a lower limit. Private browsing, storage eviction and memory pressure can prevent caching or loading. Errors are shown explicitly. After caching, inference needs no server or API key. Native builds bundle the verified default weights and use Metal on device, CPU on Simulator.

Code and prompts go to the local inference engine. The download endpoint receives the model-download request. The model can make mistakes; review and run proposed code before relying on it.

## Execution and export limits

- Python executes through CPython in both editions. Browser JavaScript runs in a worker inside a sandboxed iframe. Java and C++ are edited/exported and compiled with their own toolchains; the app does not simulate their execution.
- Python runs in a temporary workspace. Source edits are saved; files created by a running program are temporary. Browser Python stops by worker termination. Native Stop and the execution budget are checked while Python bytecode runs; a blocking native extension can delay cancellation. Native Python is not a security sandbox for hostile programs.
- Java/C++ conversion supports a typed subset: scalar values, homogeneous lists, functions, ordinary classes, conditions, range/list loops and one-generator comprehensions. Imports, dictionaries, slices, default parameters, arbitrary decorators, dynamic types and arbitrary methods need target-specific work. Declare variables outside a conditional/loop if later code uses them.
- Exported Java uses `Main.java`; C++ requires C++17. Numeric sizes, Unicode behavior, float formatting, object/list representation and some inheritance patterns differ. Compile and review exported code for the intended inputs. GUI exports require their named desktop framework; they do not run inside iOS.
- External websites decide whether to allow iframe embedding. Rey Browser includes an external-browser link. The SwiftUI app opens external sites through the system browser.
- Installed GUI packages are Rey OS designs, not operating-system executables. Browser storage can be evicted; export projects for backups.

## Verification

```sh
npm test
npm run test:wasm
npx playwright install --with-deps chromium
npm run test:web
npm run test:ai
```

`npm test` executes Python and compiles/runs C++ fixtures. Java fixtures run when `javac` is installed; CI requires it. `test:wasm` exercises actual Pyodide. `test:web` covers apps, IDE runs/files, AI edit review, designer bindings, browser framing and mobile controls; its review-guard reply is explicitly a UI fixture.

`test:ai` downloads and verifies the default GGUF, imports it into a real browser, generates and applies Python code, executes it, and checks cancellation/unloading. It also exercises the default browser download and an offline page restart with cached model inference and Python execution. Allow space for the downloaded weights and the browser cache. Native XCTest covers the actual bundled runtime/model; native UI tests exercise all 13 app screens, IDE editing/persistence and model-generated code through the interface.

See `REIMPLEMENTATION.md` for evidence and pending checks. Passing some tests does not establish that every feature works.

## Workflows

The published `codex/rey-os-reimplementation` branch runs web checks and the native build. [Draft PR #4](https://github.com/rvmendillo/portfolio/pull/4) contains the changes. Pages deployment targets `main`; review and merge changes before updating the site. The earlier `ios/` web wrapper remains a separate target.
