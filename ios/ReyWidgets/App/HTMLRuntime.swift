import SwiftUI
import WebKit

enum HTMLRuntime {
    static func page(_ doc: WidgetDocument, data: Data, size: WidgetSize) -> String {
        // Base64 avoids </script>, quote, and Unicode injection from API responses.
        let payload = data.base64EncodedString()
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        <style>html,body{width:100%;height:100%;margin:0;overflow:hidden;box-sizing:border-box}*{box-sizing:inherit}</style>
        <style>\(doc.css)</style>
        <script>
        window.__rwError = null;
        window.addEventListener('error',e=>{window.__rwError=e.message;});
        window.addEventListener('unhandledrejection',e=>{window.__rwError=String(e.reason);});
        window.widget = {
          data: JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('\(payload)'),c=>c.charCodeAt(0)))),
          size: '\(size.rawValue)', width: \(Int(size.width)), height: \(Int(size.height)),
          ready: Promise.resolve(),
          get(pointer, fallback='—') {
            if (pointer === '') return this.data;
            if (!pointer.startsWith('/')) return fallback;
            let node = this.data;
            for (const key of pointer.slice(1).split('/').map(k=>k.replace(/~1/g,'/').replace(/~0/g,'~'))) {
              if (node == null || !Object.prototype.hasOwnProperty.call(Object(node),key)) return fallback;
              node = node[key];
            }
            return node == null ? fallback : node;
          }
        };
        document.addEventListener('DOMContentLoaded',()=>{
          for (const el of document.querySelectorAll('[data-bind]')) {
            el.textContent = String(widget.get(el.getAttribute('data-bind')));
          }
        });
        </script></head><body>\(doc.html)
        <script>document.addEventListener('DOMContentLoaded',()=>{\n\(doc.javascript)\n});</script>
        </body></html>
        """
    }
    @MainActor static func webView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        return view
    }
}

struct HTMLPreview: UIViewRepresentable {
    let page: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let view = HTMLRuntime.webView(); view.navigationDelegate = context.coordinator
        view.loadHTMLString(page, baseURL: nil); context.coordinator.lastPage = page
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.lastPage != page else { return }
        context.coordinator.lastPage = page; view.loadHTMLString(page, baseURL: nil)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastPage = ""
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Only the initial document is navigable; links cannot escape the preview.
            let initial = action.navigationType == .other && action.request.url?.scheme == "about"
            decisionHandler(initial ? .allow : .cancel)
        }
    }
}

@MainActor final class SnapshotRenderer: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Data, Error>?
    private var webView: WKWebView?
    private var timeout: Task<Void, Never>?

    func render(page: String, size: WidgetSize) async throws -> Data {
        try Task.checkCancellation()
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let window = scene.windows.first(where: \.isKeyWindow) else {
            throw StudioError.message("Keep ReyWidgets open while publishing HTML.")
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let view = HTMLRuntime.webView(); self.webView = view
                view.navigationDelegate = self
                // Keep the capture surface attached and visible for WebKit's compositor.
                view.frame = CGRect(x: (window.bounds.width - size.width) / 2,
                                    y: (window.bounds.height - size.height) / 2,
                                    width: size.width, height: size.height)
                view.isUserInteractionEnabled = false
                view.layer.cornerRadius = 24; view.clipsToBounds = true
                window.addSubview(view)
                view.loadHTMLString(page, baseURL: nil)
                self.timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    self?.finish(.failure(StudioError.message("HTML rendering timed out. Check JavaScript loops or widget.ready.")))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.callAsyncJavaScript("""
        await document.fonts.ready;
        await window.widget.ready;
        await Promise.all(Array.from(document.images).map(image => image.decode().catch(() => {})));
        await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
        if (window.__rwError) throw new Error(window.__rwError);
        return true;
        """, arguments: [:], in: nil, in: .page) { [weak self, weak webView] result in
            guard let self, let webView, self.continuation != nil else { return }
            switch result {
            case .failure(let error): self.finish(.failure(error))
            case .success:
                let config = WKSnapshotConfiguration(); config.afterScreenUpdates = true
                config.rect = webView.bounds
                webView.takeSnapshot(with: config) { [weak self] image, error in
                    if let error { self?.finish(.failure(error)); return }
                    guard let data = image?.pngData() else {
                        self?.finish(.failure(StudioError.message("WebKit could not capture this widget."))); return
                    }
                    self?.finish(.success(data))
                }
            }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.navigationType == .other && action.request.url?.scheme == "about" ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(StudioError.message("HTML used too many resources. Simplify the code and try again.")))
    }
    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil; timeout?.cancel(); timeout = nil
        webView?.stopLoading(); webView?.navigationDelegate = nil; webView?.removeFromSuperview(); webView = nil
        continuation.resume(with: result)
    }
}
