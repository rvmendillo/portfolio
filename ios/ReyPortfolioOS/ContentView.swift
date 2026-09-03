import SwiftUI
import WebKit

private let portfolioURL = URL(string: "https://rvmendillo.github.io/portfolio/")!

struct ContentView: View {
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            PortfolioWebView(url: portfolioURL, isLoading: $isLoading, errorMessage: $errorMessage)
                .ignoresSafeArea()

            if isLoading {
                ProgressView("Starting Rey Portfolio OS…")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
            }

            if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 34))
                    Text("Portfolio OS could not load").font(.headline)
                    Text(errorMessage).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try again") {
                        self.errorMessage = nil
                        self.isLoading = true
                        NotificationCenter.default.post(name: .reloadPortfolioOS, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: 330)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .padding()
            }
        }
        .background(Color(red: 0.03, green: 0.07, blue: 0.12))
    }
}

private extension Notification.Name {
    static let reloadPortfolioOS = Notification.Name("reloadPortfolioOS")
}

struct PortfolioWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))
        context.coordinator.reloadObserver = NotificationCenter.default.addObserver(forName: .reloadPortfolioOS, object: nil, queue: .main) { [weak webView] _ in
            webView?.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        if let observer = coordinator.reloadObserver { NotificationCenter.default.removeObserver(observer) }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: PortfolioWebView
        var reloadObserver: NSObjectProtocol?

        init(_ parent: PortfolioWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.errorMessage = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.isLoading = false }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }

        private func fail(_ error: Error) {
            parent.isLoading = false
            parent.errorMessage = error.localizedDescription
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let requestURL = navigationAction.request.url { webView.load(URLRequest(url: requestURL)) }
            return nil
        }
    }
}
