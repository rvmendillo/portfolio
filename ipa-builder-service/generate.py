#!/usr/bin/env python3
import json,re,sys
from pathlib import Path
if len(sys.argv)!=4:raise SystemExit("usage: generate.py project.json App.swift project.yml")
project_path,app_path,project_yml_path=map(Path,sys.argv[1:]);project=json.loads(project_path.read_text());name=str(project.get("name","Generated App")).strip() or "Generated App";bundle_id=str(project.get("bundleIdentifier","com.example.generated")).strip()
if not re.fullmatch(r"[A-Za-z0-9.-]+",bundle_id):raise SystemExit("invalid bundle identifier")
components=project.get("components",[]);widget=project.get("widget") or {};widget_enabled=bool(widget.get("enabled",False))
def s(v):return str(v or "").replace("\\","\\\\").replace('"','\\"').replace("\n","\\n")
def ident(v):return "c"+re.sub(r"[^A-Za-z0-9]","",str(v))[:18]
def fnum(v,d):
 try:return float(v)
 except:return d
imports=["import SwiftUI","import Foundation","import UIKit"]
if any(c.get("kind")=="Web View" for c in components):imports.append("import WebKit")
if any(c.get("kind")=="Map" for c in components):imports.append("import MapKit")
lines=imports+["","@main","struct GeneratedApp: App {","    var body: some Scene {","        WindowGroup { ContentView() }","    }","}","","struct ContentView: View {"]
for c in components:
 cid=ident(c.get("id","x"));kind=c.get("kind","")
 if kind in ("Text Field","Secure Field","Text Editor"):lines.append(f'    @State private var {cid}Text = ""')
 elif kind=="Toggle":lines.append(f"    @State private var {cid}On = {str(bool(c.get('isOn',True))).lower()}")
 elif kind=="Slider":lines.append(f"    @State private var {cid}Value = {fnum(c.get('value'),.5)}")
 elif kind=="Stepper":lines.append(f"    @State private var {cid}Count = 1")
 elif kind=="Picker":lines.append(f'    @State private var {cid}Choice = "{s((c.get("options") or ["One"])[0])}"')
 elif kind=="Date Picker":lines.append(f"    @State private var {cid}Date = Date()")
 elif kind=="Color Picker":lines.append(f"    @State private var {cid}Color = Color.indigo")
lines += ['    @State private var showAlert = false','    @State private var alertTitle = "Notice"','    @State private var alertMessage = ""','    @State private var globalCount = 0','    var body: some View {','        GeometryReader { _ in','            ZStack(alignment: .topLeading) {']
def actions(items,indent="                    "):
 out=[]
 for a in items or []:
  k=a.get("kind","");key=s(a.get("key",""));v=s(a.get("value",""))
  if k=="Show Alert":out += [f'{indent}alertTitle = "{key or "Notice"}"',f'{indent}alertMessage = "{v}"',f'{indent}showAlert = true']
  elif k=="Set Variable":out.append(f'{indent}UserDefaults.standard.set("{v}", forKey: "{key}")')
  elif k=="Toggle Variable":out.append(f'{indent}UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "{key}"), forKey: "{key}")')
  elif k=="Increment":out.append(f'{indent}globalCount += 1')
  elif k=="Decrement":out.append(f'{indent}globalCount -= 1')
  elif k in ("Open URL","Navigate"):out.append(f'{indent}if let url = URL(string: "{v}") {{ UIApplication.shared.open(url) }}')
  elif k=="Save Locally":out.append(f'{indent}UserDefaults.standard.set("{v}", forKey: "{key}")')
  elif k=="GET Request":out.append(f'{indent}if let url = URL(string: "{v}") {{ Task {{ _ = try? await URLSession.shared.data(from: url) }} }}')
  elif k=="Copy Text":out.append(f'{indent}UIPasteboard.general.string = "{v}"')
 if not out:out.append(f'{indent}// No action configured')
 return out
for c in components:
 kind=c.get("kind","");text=s(c.get("text",""));detail=s(c.get("detail",""));cid=ident(c.get("id","x"));w=fnum(c.get("width"),200);h=fnum(c.get("height"),50);x=fnum(c.get("x"),195);y=fnum(c.get("y"),120);radius=fnum(c.get("cornerRadius"),14);value=fnum(c.get("value"),.5);p="                ";view=[]
 if kind=="Text":view=[f'{p}Text("{text}").font(.system(size: {fnum(c.get("fontSize"),17):.1f}, weight: .semibold))']
 elif kind=="Button":view=[f'{p}Button {{']+actions(c.get("actions"),p+"    ")+[f'{p}}} label: {{',f'{p}    Text("{text}").font(.headline).frame(maxWidth: .infinity, maxHeight: .infinity)',f'{p}}}',f'{p}.buttonStyle(.plain)',f'{p}.background(Color.accentColor, in: RoundedRectangle(cornerRadius: {radius:.1f}))',f'{p}.foregroundStyle(.white)']
 elif kind=="Text Field":view=[f'{p}TextField("{text}", text: ${cid}Text).textFieldStyle(.roundedBorder)']
 elif kind=="Secure Field":view=[f'{p}SecureField("{text}", text: ${cid}Text).textFieldStyle(.roundedBorder)']
 elif kind=="Text Editor":view=[f'{p}TextEditor(text: ${cid}Text).overlay {{ RoundedRectangle(cornerRadius: 8).stroke(.quaternary) }}']
 elif kind=="Image":view=[f'{p}Image(systemName: "{text or "photo"}").resizable().scaledToFit().padding(8)']
 elif kind=="SF Symbol":view=[f'{p}Image(systemName: "{text or "sparkles"}").font(.system(size: 44)).foregroundStyle(.tint)']
 elif kind=="Label":view=[f'{p}Label("{text}", systemImage: "{detail or "star.fill"}")']
 elif kind=="Toggle":view=[f'{p}Toggle("{text}", isOn: ${cid}On)']
 elif kind=="Slider":view=[f'{p}VStack(alignment: .leading) {{ Text("{text}").font(.caption); Slider(value: ${cid}Value) }}']
 elif kind=="Stepper":view=[f'{p}Stepper("{text}: \\({cid}Count)", value: ${cid}Count)']
 elif kind=="Picker":
  opts=c.get("options") or ["One","Two","Three"];optcode="; ".join([f'Text("{s(o)}").tag("{s(o)}")' for o in opts]);view=[f'{p}Picker("{text}", selection: ${cid}Choice) {{ {optcode} }}']
 elif kind=="Date Picker":view=[f'{p}DatePicker("{text}", selection: ${cid}Date)']
 elif kind=="Color Picker":view=[f'{p}ColorPicker("{text}", selection: ${cid}Color)']
 elif kind=="Progress View":view=[f'{p}VStack {{ ProgressView(value: {value:.3f}); Text("{text}").font(.caption) }}']
 elif kind=="Gauge":view=[f'{p}Gauge(value: {value:.3f}) {{ Text("{text}") }}.gaugeStyle(.accessoryCircular)']
 elif kind=="Divider":view=[f'{p}Divider()']
 elif kind=="Spacer":view=[f'{p}Color.clear.overlay {{ Label("Spacer", systemImage: "arrow.up.and.down").font(.caption).foregroundStyle(.secondary) }}']
 elif kind=="Link":view=[f'{p}Link(destination: URL(string: "{detail or "https://example.com"}")!) {{ Label("{text}", systemImage: "link") }}']
 elif kind=="Menu":view=[f'{p}Menu("{text}") {{ Button("Option 1") {{ }}; Button("Option 2") {{ }} }}']
 elif kind=="Navigation Link":view=[f'{p}Button {{ if let url = URL(string: "{detail or "reyforge://detail"}") {{ UIApplication.shared.open(url) }} }} label: {{ HStack {{ Text("{text}"); Spacer(); Image(systemName: "chevron.right") }} }}']
 elif kind=="List":view=[f'{p}VStack(spacing: 0) {{ ForEach(1...4, id: \\.self) {{ i in HStack {{ Text("{text} \\(i)"); Spacer() }}.padding(8); Divider() }} }}.background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))']
 elif kind=="Scroll View":view=[f'{p}ScrollView {{ VStack {{ ForEach(1...8, id: \\.self) {{ Text("Scrollable item \\($0)").padding(5) }} }} }}']
 elif kind=="VStack":view=[f'{p}VStack {{ Text("{text}"); RoundedRectangle(cornerRadius: 6).fill(.quaternary); RoundedRectangle(cornerRadius: 6).fill(.quaternary) }}.padding(8)']
 elif kind=="HStack":view=[f'{p}HStack {{ Text("{text}"); RoundedRectangle(cornerRadius: 6).fill(.quaternary); RoundedRectangle(cornerRadius: 6).fill(.quaternary) }}.padding(8)']
 elif kind=="ZStack":view=[f'{p}ZStack {{ RoundedRectangle(cornerRadius: 12).fill(.tint.opacity(0.12)); Circle().fill(.tint.opacity(0.2)).padding(18); Text("{text}") }}']
 elif kind=="Form":view=[f'{p}VStack(alignment: .leading) {{ Text("{text}").font(.headline); TextField("Field", text: .constant("")); Toggle("Option", isOn: .constant(true)) }}.padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))']
 elif kind=="Section":view=[f'{p}VStack(alignment: .leading) {{ Text("{text}").font(.caption).foregroundStyle(.secondary); Divider(); Text("Section content") }}.padding(10)']
 elif kind=="Capsule":view=[f'{p}Capsule().fill(.tint.opacity(0.18)).overlay {{ Text("{text}") }}']
 elif kind=="Rounded Rectangle":view=[f'{p}RoundedRectangle(cornerRadius: {radius:.1f}).fill(.tint.opacity(0.18)).overlay {{ Text("{text}") }}']
 elif kind=="Circle":view=[f'{p}Circle().fill(.tint.opacity(0.18)).overlay {{ Text("{text}").font(.caption) }}']
 elif kind=="Web View":view=[f'{p}WebView(urlString: "{detail or "https://apple.com"}")']
 elif kind=="Map":view=[f'{p}Map(initialPosition: .automatic)']
 elif kind=="Share Link":view=[f'{p}ShareLink(item: "{detail or text}") {{ Label("{text}", systemImage: "square.and.arrow.up") }}']
 else:view=[f'{p}Text("{s(kind)}")']
 lines += view+[f'{p}    .frame(width: {w:.1f}, height: {h:.1f})',f'{p}    .position(x: {x:.1f}, y: {y:.1f})']
lines += ['            }','            .frame(width: 390, height: 844, alignment: .topLeading)','        }','        .alert(alertTitle, isPresented: $showAlert) { Button("OK", role: .cancel) {} } message: { Text(alertMessage) }','    }','}']
if any(c.get("kind")=="Web View" for c in components):lines += ["","struct WebView: UIViewRepresentable {","    let urlString: String","    func makeUIView(context: Context) -> WKWebView { WKWebView() }","    func updateUIView(_ view: WKWebView, context: Context) {","        guard let url = URL(string: urlString) else { return }","        if view.url != url { view.load(URLRequest(url: url)) }","    }","}"]
app_path.parent.mkdir(parents=True,exist_ok=True);app_path.write_text("\n".join(lines)+"\n");safe_name=name.replace('"','');deps="";widget_target=""
if widget_enabled:
 deps="""    dependencies:\n      - target: GeneratedWidget\n        embed: true\n        codeSign: false\n""";widget_target=f"""\n  GeneratedWidget:\n    type: app-extension\n    platform: iOS\n    sources:\n      - path: Widget.swift\n    settings:\n      base:\n        PRODUCT_BUNDLE_IDENTIFIER: {bundle_id}.widget\n        PRODUCT_NAME: GeneratedWidget\n        INFOPLIST_FILE: WidgetInfo.plist\n        SKIP_INSTALL: YES\n        APPLICATION_EXTENSION_API_ONLY: YES\n        TARGETED_DEVICE_FAMILY: \"1,2\"\n"""
project_yml=f"""name: GeneratedApp\noptions:\n  deploymentTarget:\n    iOS: \"17.0\"\nsettings:\n  base:\n    SWIFT_VERSION: \"5.0\"\ntargets:\n  GeneratedApp:\n    type: application\n    platform: iOS\n    sources:\n      - path: App.swift\n{deps}    settings:\n      base:\n        PRODUCT_BUNDLE_IDENTIFIER: {bundle_id}\n        PRODUCT_NAME: GeneratedApp\n        MARKETING_VERSION: \"1.0\"\n        CURRENT_PROJECT_VERSION: \"1\"\n        TARGETED_DEVICE_FAMILY: \"1,2\"\n        GENERATE_INFOPLIST_FILE: YES\n        INFOPLIST_KEY_CFBundleDisplayName: \"{safe_name}\"\n        INFOPLIST_KEY_UILaunchScreen_Generation: YES\n        INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents: YES\n{widget_target}""";project_yml_path.write_text(project_yml)
if widget_enabled:
 title=s(widget.get("title",name));subtitle=s(widget.get("subtitle","Built with ReyForge"));symbol=s(widget.get("symbol","sparkles"));display=s(widget.get("displayName","Widget"));family=widget.get("family","systemMedium");family=family if family in ("systemSmall","systemMedium","systemLarge") else "systemMedium";deep=s(widget.get("deepLink","reyforge://home"))
 (app_path.parent/"Widget.swift").write_text(f'''import WidgetKit\nimport SwiftUI\nstruct ReyForgeEntry: TimelineEntry {{ let date: Date }}\nstruct ReyForgeProvider: TimelineProvider {{\n func placeholder(in context: Context)->ReyForgeEntry{{ReyForgeEntry(date:Date())}}\n func getSnapshot(in context: Context,completion:@escaping(ReyForgeEntry)->Void){{completion(ReyForgeEntry(date:Date()))}}\n func getTimeline(in context: Context,completion:@escaping(Timeline<ReyForgeEntry>)->Void){{let e=ReyForgeEntry(date:Date());completion(Timeline(entries:[e],policy:.after(Date().addingTimeInterval(900))))}}\n}}\nstruct ReyForgeWidgetView: View {{ var entry:ReyForgeProvider.Entry; var body:some View {{ Link(destination:URL(string:"{deep}")!){{HStack(spacing:12){{Image(systemName:"{symbol}").font(.title).foregroundStyle(.tint);VStack(alignment:.leading,spacing:3){{Text("{title}").font(.headline);Text("{subtitle}").font(.caption).foregroundStyle(.secondary).lineLimit(2)}};Spacer()}}}}.containerBackground(.fill.tertiary,for:.widget) }} }}\n@main struct GeneratedWidget: Widget {{ let kind="{bundle_id}.widget"; var body:some WidgetConfiguration {{ StaticConfiguration(kind:kind,provider:ReyForgeProvider()){{entry in ReyForgeWidgetView(entry:entry)}}.configurationDisplayName("{display}").description("A Home Screen widget generated by ReyForge.").supportedFamilies([.{family}]) }} }}\n''')
 (app_path.parent/"WidgetInfo.plist").write_text('''<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>CFBundleDisplayName</key><string>GeneratedWidget</string><key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string><key>CFBundleInfoDictionaryVersion</key><string>6.0</string><key>CFBundleName</key><string>$(PRODUCT_NAME)</string><key>CFBundlePackageType</key><string>XPC!</string><key>CFBundleShortVersionString</key><string>1.0</string><key>CFBundleVersion</key><string>1</string><key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict></dict></plist>\n''')
