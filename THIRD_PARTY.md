# Third-party components

Versions are pinned in `package-lock.json`, `shared/model.json` and `scripts/prepare-native.py`. Preserve upstream notices when distributing their runtimes or weights.

| Component | Source | Upstream license |
| --- | --- | --- |
| CodeMirror 6 | https://github.com/codemirror | MIT |
| Wllama 3.6.1 | https://github.com/ngxson/wllama | MIT |
| Pyodide 314.0.6 | https://github.com/pyodide/pyodide | MPL-2.0 |
| CPython / Python Apple Support 3.14-b11 | https://github.com/beeware/Python-Apple-support | Python and bundled dependencies retain upstream licenses |
| llama.cpp b10927 | https://github.com/ggml-org/llama.cpp | MIT |
| Qwen2.5 Coder 0.5B Instruct GGUF | https://huggingface.co/Qwen/Qwen2.5-Coder-0.5B-Instruct-GGUF | Apache-2.0 |

No third-party runtime source changes are required. The build preserves JavaScript license comments and copies Pyodide. This reimplementation does not assign a license to the user's source.
