import SwiftUI
import PDFKit

struct NativeAboutView: View {
    @EnvironmentObject private var theme: ThemeStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    ZStack { RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [.cyan, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)); Text("RV").font(.largeTitle.bold()).foregroundStyle(.white) }
                        .frame(width: 100, height: 100)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("SOFTWARE ENGINEER · AI BUILDER").font(.caption2.bold()).tracking(1).foregroundStyle(theme.accent)
                        Text("Rey Victor Mendillo").font(.title.bold())
                        Text("Building enterprise cargo systems, intelligent tools, and interfaces where rigorous engineering meets human-centered design.").font(.subheadline).foregroundStyle(theme.secondary)
                    }
                }.padding().nativeCard(corner: 22)
                HStack(spacing: 10) {
                    StatCard(value: "3+ years", label: "Engineering")
                    StatCard(value: "AI + enterprise", label: "Focus")
                    StatCard(value: "Mapúa", label: "BS Computer Science")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("CURRENT").font(.caption2.bold()).tracking(1).foregroundStyle(theme.accent)
                    Text("Software Engineer at CHAMP Cargosystems").font(.title3.bold())
                    Text("Working across Angular, Java, Spring, APIs, OAuth, search, caching, Oracle, and reusable product systems for air cargo.").foregroundStyle(theme.secondary)
                }.padding().nativeCard()
                VStack(alignment: .leading, spacing: 14) {
                    Text("EXPERIENCE").font(.caption2.bold()).tracking(1).foregroundStyle(theme.accent)
                    ExperienceRow(year: "2025 — present", role: "Software Engineer", company: "CHAMP Cargosystems")
                    ExperienceRow(year: "2023 — 2025", role: "Junior Software Engineer", company: "CHAMP Cargosystems")
                    ExperienceRow(year: "2021", role: "Associate Back-End Developer", company: "Chimes Consulting")
                }.padding().nativeCard()
                HStack {
                    Link(destination: URL(string: "mailto:rvmendillo@gmail.com")!) { Label("Email", systemImage: "envelope.fill") }
                    Spacer()
                    Link(destination: URL(string: "https://ph.linkedin.com/in/rvmendillo")!) { Label("LinkedIn", systemImage: "person.text.rectangle") }
                    Spacer()
                    Link(destination: URL(string: "https://github.com/rvmendillo")!) { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                }.font(.caption.bold()).padding().nativeCard()
            }.padding(16)
        }
    }
}

private struct StatCard: View {
    @EnvironmentObject private var theme: ThemeStore
    let value: String; let label: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(.caption.bold()).minimumScaleFactor(0.7); Text(label).font(.caption2).foregroundStyle(theme.secondary).lineLimit(2) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).nativeCard(corner: 14) }
}
private struct ExperienceRow: View {
    @EnvironmentObject private var theme: ThemeStore
    let year: String; let role: String; let company: String
    var body: some View { HStack { Text(year).font(.caption).foregroundStyle(theme.accent).frame(width: 110, alignment: .leading); VStack(alignment: .leading) { Text(role).font(.subheadline.bold()); Text(company).font(.caption).foregroundStyle(theme.secondary) }; Spacer() }.padding(.vertical, 4) }
}

struct NativeProjectsView: View {
    @EnvironmentObject private var theme: ThemeStore
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 13) {
                ForEach(portfolioProjects) { project in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(project.category).font(.caption2.bold()).tracking(1).foregroundStyle(theme.accent); Spacer(); Text(project.number).font(.largeTitle.bold()).foregroundStyle(theme.secondary.opacity(0.22)) }
                        Text(project.title).font(.title2.bold())
                        Text(project.summary).font(.subheadline).foregroundStyle(theme.secondary)
                        ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(project.tags, id: \.self) { Text($0).font(.caption2.bold()).padding(.horizontal, 9).padding(.vertical, 6).background(theme.accent.opacity(0.13), in: Capsule()) } } }
                    }.padding(18).nativeCard(corner: 20)
                }
            }.padding(16)
        }
    }
}

struct NativeResumeView: View {
    @EnvironmentObject private var theme: ThemeStore
    var body: some View {
        VStack(spacing: 0) {
            if let url = Bundle.main.url(forResource: "Resume", withExtension: "pdf") {
                HStack {
                    Label("Bundled for offline viewing", systemImage: "checkmark.icloud.fill").font(.caption).foregroundStyle(theme.secondary)
                    Spacer()
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up").font(.caption.bold()) }
                }.padding(12).background(.ultraThinMaterial)
                PDFKitView(url: url)
            } else {
                ContentUnavailableViewCompat(title: "Resume unavailable", symbol: "doc.text.magnifyingglass", message: "The bundled PDF could not be opened.")
            }
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.displayDirection = .vertical
        view.document = PDFDocument(url: url); return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}

struct NativeFilesView: View {
    @EnvironmentObject private var theme: ThemeStore
    private let groups: [(String, [(String, String, String)])] = [
        ("Portfolio", [("Resume.pdf", "PDF document", "doc.text.fill"), ("About Rey", "Profile", "person.crop.square"), ("Projects", "4 selected works", "square.stack.3d.up")]),
        ("Developer", [("main.py", "Python source", "chevron.left.forwardslash.chevron.right"), ("gui.yml", "GUI definition", "square.on.square.dashed"), ("Transpiler.exe", "Native feature clone", "arrow.left.arrow.right.square")])
    ]
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: "internaldrive.fill").foregroundStyle(theme.accent); VStack(alignment: .leading) { Text("Portfolio (Local)").bold(); Text("Files bundled with the native app").font(.caption).foregroundStyle(theme.secondary) }; Spacer() }.padding().nativeCard()
            ForEach(groups, id: \.0) { group in VStack(alignment: .leading, spacing: 8) { Text(group.0.uppercased()).font(.caption2.bold()).tracking(1).foregroundStyle(theme.secondary); ForEach(group.1, id: \.0) { item in HStack(spacing: 12) { Image(systemName: item.2).frame(width: 38, height: 38).background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading) { Text(item.0).font(.subheadline.bold()); Text(item.1).font(.caption).foregroundStyle(theme.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.secondary) }.padding(11).nativeCard(corner: 14) } } }
        }.padding(16) }
    }
}

struct NativeBrowserView: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var page = "Home"
    let pages = ["Home", "About", "Projects", "Developer"]
    var body: some View {
        VStack(spacing: 12) {
            HStack { Button { page = pages[max(0, (pages.firstIndex(of: page) ?? 0) - 1)] } label: { Image(systemName: "chevron.left") }; Image(systemName: "lock.fill").font(.caption); Text("portfolio://\(page.lowercased())").font(.caption.monospaced()).lineLimit(1); Spacer(); Image(systemName: "arrow.clockwise") }.padding(12).nativeCard(corner: 16).padding(.horizontal, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Image(systemName: "safari.fill").font(.system(size: 52)).foregroundStyle(theme.accent)
                    Text(page == "Home" ? "Rey on the web" : page).font(.largeTitle.bold())
                    Text(browserCopy).foregroundStyle(theme.secondary)
                    ForEach(pages, id: \.self) { item in Button { withAnimation { page = item } } label: { HStack { VStack(alignment: .leading) { Text(item).bold(); Text("portfolio://\(item.lowercased())").font(.caption).foregroundStyle(theme.secondary) }; Spacer(); Image(systemName: "arrow.right") }.padding().nativeCard() }.buttonStyle(.plain) }
                    Link(destination: URL(string: "https://github.com/rvmendillo")!) { Label("Open GitHub in Safari", systemImage: "safari") }.buttonStyle(.borderedProminent).tint(theme.accent)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
        }.padding(.top, 12)
    }
    private var browserCopy: String {
        switch page { case "About": return "Software Engineer at CHAMP Cargosystems, building enterprise and intelligent systems."; case "Projects": return "Skyler, Gesture Cursor, Rotational Churn, and Text Summarization."; case "Developer": return "Safe terminal, native IDE, GUI Designer, and HumanCode Transpiler."; default: return "A fully native navigator for Rey’s portfolio, with trusted external links opening in Safari." }
    }
}

struct NativeSettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    private let accents = ["59A8FF", "7C6CFF", "36D6B0", "FF6F91", "F2A43C"]
    var body: some View {
        Form {
            Section("Profile") { TextField("Profile name", text: $theme.profileName).textInputAutocapitalization(.words) }
            Section("Theme") { ForEach(PortfolioTheme.allCases) { option in Button { withAnimation(.easeInOut(duration: 0.35)) { theme.selectedTheme = option } } label: { HStack { VStack(alignment: .leading) { Text(option.title); Text(option.subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); if theme.selectedTheme == option { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent) } } } } }
            Section("Accent") { HStack { ForEach(accents, id: \.self) { value in Button { theme.accentHex = value } label: { Circle().fill(Color(hex: value)).frame(width: 34, height: 34).overlay(Circle().stroke(.white, lineWidth: theme.accentHex == value ? 3 : 0)) } }.buttonStyle(.plain) } }
            Section("Accessibility") { Toggle("Animations and transitions", isOn: $theme.motionEnabled); Text("The system Reduce Motion setting is always respected.").font(.caption).foregroundStyle(.secondary) }
            Section("Privacy & security") { Label("No web view or remote AI endpoint", systemImage: "lock.shield.fill"); Label("Validated local arithmetic and packages", systemImage: "checkmark.seal.fill"); Label("Profile data stays in UserDefaults", systemImage: "iphone.and.arrow.forward") }
            Section { Button("Reset native settings", role: .destructive) { theme.reset() } }
        }.scrollContentBackground(.hidden)
    }
}

struct NativeCalculatorView: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var expression = ""
    @State private var display = "0"
    private let keys = ["AC", "±", "%", "÷", "7", "8", "9", "×", "4", "5", "6", "−", "1", "2", "3", "+", "0", "0", ".", "="]
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            VStack(alignment: .trailing) { Text(expression).font(.caption).foregroundStyle(theme.secondary).frame(maxWidth: .infinity, alignment: .trailing); Text(display).font(.system(size: 54, weight: .light, design: .rounded)).lineLimit(1).minimumScaleFactor(0.45) }.padding()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in Button { tap(key) } label: { Text(key).font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 58).background(operatorKeys.contains(key) ? theme.accent : .white.opacity(0.09), in: RoundedRectangle(cornerRadius: 15)).foregroundStyle(operatorKeys.contains(key) ? .black : theme.primary) }.buttonStyle(SpringButtonStyle()) }
            }
        }.padding(18)
    }
    private var operatorKeys: Set<String> { ["÷", "×", "−", "+", "="] }
    private func tap(_ key: String) {
        switch key {
        case "AC": expression = ""; display = "0"
        case "±": if let number = Double(display) { display = MathFormatter.string(-number); expression = display }
        case "%": if let number = Double(display) { display = MathFormatter.string(number / 100); expression = display }
        case "=": do { let value = try SafeMath.evaluate(expression); display = MathFormatter.string(value); expression += " =" } catch { display = "Error"; expression = "" }
        default: let normalized = key == "÷" ? "/" : key == "×" ? "*" : key == "−" ? "-" : key; if expression.count < 100 { expression += normalized; display = expression }
        }
    }
}

struct ContentUnavailableViewCompat: View {
    let title: String; let symbol: String; let message: String
    var body: some View { VStack(spacing: 12) { Image(systemName: symbol).font(.system(size: 44)); Text(title).font(.headline); Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding() }
}
