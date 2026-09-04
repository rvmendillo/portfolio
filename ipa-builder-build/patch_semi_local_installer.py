from pathlib import Path

p = Path(__file__).with_name("LocalhostInstaller.swift")
s = p.read_text()

s = s.replace("private enum LocalInstallMode {", "private enum LocalInstallMode: Equatable {", 1)
s = s.replace("supportsFullyLocal = Self.detectFullyLocalEntitlements()", "supportsFullyLocal = false", 1)

start = s.index("    private func compatibilityInstallPageData() throws -> Data {")
end = s.index("    private func sendSimple(", start)
replacement = r'''    private func compatibilityInstallPageData() throws -> Data {
        let payload = "http://127.0.0.1:\(port.rawValue)/\(token)/app.ipa"
        let baseURL = "https://api.palera.in/genPlist?bundleid=\(activeBundleIdentifier)&name=ReyForge Signed App&version=1.0&fetchurl=\(payload)"

        guard let encodedOnce = baseURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedTwice = encodedOnce.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            throw LocalInstallError.manifestURLFailed
        }

        let installURL = "itms-services://?action=download-manifest&url=\(encodedTwice)"
        let htmlURL = installURL.replacingOccurrences(of: "&", with: "&amp;")
        let html = """
        <html style="background-color:#111;color:white;font-family:-apple-system">
          <head><meta name="viewport" content="width=device-width, initial-scale=1"><title>ReyForge Install</title></head>
          <body style="padding:24px">
            <h2>Open in iTunes</h2>
            <p>ReyForge is handing the signed IPA to the iOS installer.</p>
            <p><a href="\(htmlURL)">Open in iTunes</a></p>
            <script>setTimeout(function(){ window.location="\(installURL)"; }, 150);</script>
          </body>
        </html>
        """
        return Data(html.utf8)
    }

'''
s = s[:start] + replacement + s[end:]
s = s.replace('contentType: "text/html; charset=utf-8"', 'contentType: "text/html"', 1)

header_start = s.index("    private func responseHeader(status: String, contentType: String, length: Int) -> String {")
header_end = s.index("    private func beginBackgroundTask()", header_start)
header = r'''    private func responseHeader(status: String, contentType: String, length: Int) -> String {
        "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(length)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
    }

'''
s = s[:header_start] + header + s[header_end:]

if "Open in iTunes" not in s or "encodedTwice" not in s:
    raise SystemExit("installer patch validation failed")

p.write_text(s)
