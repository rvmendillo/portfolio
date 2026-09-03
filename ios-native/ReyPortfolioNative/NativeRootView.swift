import SwiftUI

struct NativeRootView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var booting = true

    var body: some View {
        ZStack {
            NativeDesktopView()
            if booting {
                NativeBootView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(20)
            }
        }
        .onAppear {
            let delay = theme.motionEnabled && !reduceMotion ? 1.55 : 0.15
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.55)) { booting = false }
            }
        }
    }
}

private struct NativeBootView: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var spinning = false

    var body: some View {
        ZStack {
            Color(hex: "040A13").ignoresSafeArea()
            Circle()
                .fill(AngularGradient(colors: [.cyan.opacity(0.22), .indigo.opacity(0.3), .mint.opacity(0.18), .cyan.opacity(0.22)], center: .center))
                .frame(width: 330, height: 330).blur(radius: 35)
                .rotationEffect(.degrees(spinning ? 180 : 0)).scaleEffect(spinning ? 1.12 : 0.88)
            VStack(spacing: 24) {
                WindowsMark().frame(width: 76, height: 76)
                    .shadow(color: .blue.opacity(0.55), radius: 28)
                Text("REY PORTFOLIO NATIVE").font(.caption.weight(.bold)).tracking(3.2).foregroundStyle(.white.opacity(0.86))
                ProgressView().tint(.cyan)
                Text("SwiftUI · local-first").font(.caption2).foregroundStyle(.white.opacity(0.46))
            }
        }
        .onAppear {
            guard theme.motionEnabled else { return }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { spinning = true }
        }
    }
}

struct NativeDesktopView: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var selectedApp: NativeAppKind?
    @State private var search = ""
    @State private var showSearch = false
    private let columns = [GridItem(.adaptive(minimum: 82, maximum: 116), spacing: 14)]

    var filteredApps: [NativeAppKind] {
        search.isEmpty ? NativeAppKind.allCases : NativeAppKind.allCases.filter { ($0.title + " " + $0.subtitle).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            AuroraBackground()
            ScrollView {
                VStack(spacing: 20) {
                    desktopHeader
                    if showSearch {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                            TextField("Search apps and portfolio", text: $search)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showSearch = false; search = "" } } label: { Image(systemName: "xmark.circle.fill") }
                        }
                        .padding(12).background(theme.panel, in: RoundedRectangle(cornerRadius: 16))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    hero
                    LazyVGrid(columns: columns, spacing: 17) {
                        ForEach(filteredApps) { app in AppTile(app: app) { selectedApp = app } }
                    }
                    .padding(.bottom, 90)
                }
                .padding(.horizontal, 18).padding(.top, 8)
            }
            VStack { Spacer(); nativeDock }
        }
        .foregroundStyle(theme.primary)
        .sheet(item: $selectedApp) { app in
            NativeAppShell(app: app) { selectedApp = nil }
                .environmentObject(theme)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    private var desktopHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 7, height: 7).shadow(color: .green, radius: 5)
                Text("Rey Portfolio Native").font(.caption.weight(.semibold))
            }
            Spacer()
            Button { withAnimation(.spring(response: 0.35)) { showSearch.toggle() } } label: { Image(systemName: "magnifyingglass") }
            Button { selectedApp = .assistant } label: { Image(systemName: "sparkles") }
        }
        .buttonStyle(.plain).foregroundStyle(theme.secondary)
    }

    private var hero: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [.cyan, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("RV").font(.title.bold()).foregroundStyle(.white)
            }.frame(width: 76, height: 76).shadow(color: .blue.opacity(0.35), radius: 22, y: 10)
            VStack(alignment: .leading, spacing: 5) {
                Text("SOFTWARE ENGINEER · AI BUILDER").font(.caption2.bold()).tracking(1.1).foregroundStyle(theme.accent)
                Text(theme.profileName).font(.title2.bold())
                Text("Enterprise systems, intelligent tools, and human-centered interfaces.").font(.footnote).foregroundStyle(theme.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(18).background(theme.panel, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12)))
    }

    private var nativeDock: some View {
        HStack(spacing: 8) {
            ForEach([NativeAppKind.about, .projects, .terminal, .designer, .settings]) { app in
                Button { selectedApp = app } label: {
                    Image(systemName: app.symbol).font(.system(size: 19, weight: .semibold)).frame(width: 45, height: 45)
                        .background(app.tint.gradient, in: RoundedRectangle(cornerRadius: 13))
                        .foregroundStyle(app == .files || app == .calculator ? .black : .white)
                }.buttonStyle(SpringButtonStyle())
            }
        }
        .padding(9).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.16)))
        .padding(.bottom, 7).shadow(color: .black.opacity(0.26), radius: 25, y: 12)
    }
}

private struct AuroraBackground: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var animate = false
    var body: some View {
        ZStack {
            Circle().fill(.blue.opacity(0.2)).frame(width: 310).blur(radius: 55).offset(x: animate ? 130 : -120, y: animate ? -180 : -80)
            Circle().fill(.mint.opacity(0.14)).frame(width: 290).blur(radius: 60).offset(x: animate ? -110 : 140, y: animate ? 240 : 330)
            Circle().fill(.purple.opacity(0.13)).frame(width: 220).blur(radius: 50).offset(x: animate ? 80 : -90, y: 60)
        }.allowsHitTesting(false).onAppear {
            guard theme.motionEnabled else { return }
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) { animate = true }
        }
    }
}

private struct AppTile: View {
    @EnvironmentObject private var theme: ThemeStore
    let app: NativeAppKind
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: app.symbol).font(.system(size: 27, weight: .semibold)).frame(width: 58, height: 58)
                    .background(app.tint.gradient, in: RoundedRectangle(cornerRadius: 17))
                    .foregroundStyle(app == .files || app == .calculator ? .black : .white)
                    .shadow(color: app.tint.opacity(0.28), radius: 12, y: 7)
                Text(app.title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.75)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(SpringButtonStyle())
    }
}

struct NativeAppShell: View {
    @EnvironmentObject private var theme: ThemeStore
    let app: NativeAppKind
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: app.symbol).frame(width: 30, height: 30).background(app.tint.gradient, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) { Text(app.title).font(.subheadline.bold()); Text(app.subtitle).font(.caption2).foregroundStyle(theme.secondary) }
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.body.bold()).frame(width: 34, height: 34).background(.white.opacity(0.09), in: Circle()) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10).background(.ultraThinMaterial)
            Group {
                switch app {
                case .about: NativeAboutView()
                case .resume: NativeResumeView()
                case .projects: NativeProjectsView()
                case .files: NativeFilesView()
                case .browser: NativeBrowserView()
                case .terminal: NativeTerminalView()
                case .ide: NativeIDEView()
                case .designer: NativeDesignerView()
                case .transpiler: NativeTranspilerView()
                case .assistant: NativeAssistantView()
                case .studio: NativeAppStudioView()
                case .settings: NativeSettingsView()
                case .calculator: NativeCalculatorView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(theme.primary).background(theme.background.ignoresSafeArea())
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.13)))
    }
}

struct WindowsMark: View {
    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow { tile; tile }; GridRow { tile; tile }
        }
    }
    private var tile: some View { RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)) }
}

struct SpringButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.91 : 1).opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

extension View {
    func nativeCard(corner: CGFloat = 18) -> some View {
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner)).overlay(RoundedRectangle(cornerRadius: corner).stroke(.white.opacity(0.11)))
    }
}
