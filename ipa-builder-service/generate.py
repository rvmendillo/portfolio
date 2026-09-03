#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit("usage: generate.py project.json App.swift project.yml")

project_path, app_path, project_yml_path = map(Path, sys.argv[1:])
project = json.loads(project_path.read_text())

name = str(project.get("name", "Generated App")).strip() or "Generated App"
bundle_id = str(project.get("bundleIdentifier", "com.example.generated")).strip()
if not re.fullmatch(r"[A-Za-z0-9.-]+", bundle_id):
    raise SystemExit("invalid bundle identifier")

def swift_string(value):
    s = str(value)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

lines = [
    "import SwiftUI",
    "",
    "@main",
    "struct GeneratedApp: App {",
    "    var body: some Scene {",
    "        WindowGroup { ContentView() }",
    "    }",
    "}",
    "",
    "struct ContentView: View {",
    '    @State private var input = ""',
    "    var body: some View {",
    "        ScrollView {",
    "            VStack(spacing: 16) {",
]

for component in project.get("components", []):
    kind = component.get("kind", "")
    text = swift_string(component.get("text", ""))
    if kind == "Text":
        lines.append(f'                Text("{text}")')
    elif kind == "Button":
        lines.append(f'                Button("{text}") {{ }}')
    elif kind == "Input":
        lines.append(f'                TextField("{text}", text: $input)')
        lines.append("                    .textFieldStyle(.roundedBorder)")
    elif kind == "Image":
        lines.append(f'                Image(systemName: "{text or "photo"}")')
        lines.append("                    .font(.largeTitle)")
    elif kind == "Spacer":
        lines.append("                Spacer(minLength: 24)")

lines += [
    "            }",
    "            .padding()",
    "        }",
    "    }",
    "}",
]

app_path.parent.mkdir(parents=True, exist_ok=True)
app_path.write_text("\n".join(lines) + "\n")

safe_name = name.replace('"', "")
project_yml = f"""name: GeneratedApp
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    SWIFT_VERSION: "5.0"
targets:
  GeneratedApp:
    type: application
    platform: iOS
    sources:
      - path: App.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {bundle_id}
        PRODUCT_NAME: GeneratedApp
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
        TARGETED_DEVICE_FAMILY: "1,2"
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: "{safe_name}"
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents: YES
"""
project_yml_path.write_text(project_yml)
