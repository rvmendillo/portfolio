import Foundation

enum InstallRequest {
    static func handoffURL(identity: IPAIdentity, payloadURL: URL) throws -> URL {
        var helper = URLComponents(string: "https://api.palera.in/genPlist")!
        let values = [
            ("bundleid", identity.bundleIdentifier), ("name", identity.name),
            ("version", identity.version), ("fetchurl", payloadURL.absoluteString)
        ]
        helper.percentEncodedQuery = values.map { key, value in
            key + "=" + value.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        }.joined(separator: "&")
        guard let manifest = helper.url?.absoluteString,
              let encoded = manifest.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let result = URL(string: "itms-services://?action=download-manifest&url=" + encoded) else {
            throw IdentityError.invalidApp
        }
        return result
    }
    static func page(identity: IPAIdentity, payloadURL: URL) throws -> Data {
        let url = try handoffURL(identity: identity, payloadURL: payloadURL).absoluteString
        let js = String(decoding: try JSONEncoder().encode(url), as: UTF8.self)
        let href = url.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
        return Data("""
        <!doctype html><html lang="en"><head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Install app</title></head>
        <body style="background:#111;color:#fff;font:17px -apple-system;padding:24px">
        <h1>Install your app</h1>
        <p>Continue to the iOS installer. Keep ReyForge running until the download finishes.</p>
        <p><a style="color:#a8b6ff" href="\(href)">Open in iTunes</a></p>
        <script>setTimeout(function(){window.location=\(js);},150);</script>
        </body></html>
        """.utf8)
    }
}

struct HTTPByteRange: Equatable, Sendable {
    let start: UInt64
    let length: UInt64
    var end: UInt64 { start + length - 1 }
    init?(header: String, fileSize: UInt64) {
        guard header.hasPrefix("bytes="), fileSize > 0 else { return nil }
        let parts = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {
            guard let suffix = UInt64(parts[1]), suffix > 0 else { return nil }
            length = min(suffix, fileSize)
            start = fileSize - length
        } else {
            guard let first = UInt64(parts[0]), first < fileSize else { return nil }
            let last: UInt64
            if parts[1].isEmpty { last = fileSize - 1 }
            else {
                guard let requested = UInt64(parts[1]), requested >= first else { return nil }
                last = min(requested, fileSize - 1)
            }
            start = first
            length = last - first + 1
        }
    }
}
