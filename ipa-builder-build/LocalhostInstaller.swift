import Foundation
import SwiftUI
import Network
import Security
import UIKit

private enum LocalInstallError: LocalizedError {
    case invalidBackloopIdentity
    case signedIPAMissing
    case serverFailed(String)
    case installerURLFailed
    case manifestURLFailed

    var errorDescription: String? {
        switch self {
        case .invalidBackloopIdentity:
            return "ReyForge could not load the trusted backloop.dev TLS identity."
        case .signedIPAMissing:
            return "Sign an IPA first."
        case .serverFailed(let detail):
            return "Local install server failed: \(detail)"
        case .installerURLFailed:
            return "iOS did not accept the installation handoff."
        case .manifestURLFailed:
            return "ReyForge could not create the installation manifest URL."
        }
    }
}

private enum LocalInstallMode {
    case fullyLocalTrustedTLS
    case compatibilityLocal
}

/// Feather-style on-device installation.
///
/// Fully-local mode serves both the OTA manifest and IPA from a random
/// `*.backloop.dev` hostname. The wildcard hostname resolves to loopback and
/// uses a publicly trusted TLS certificate, so no user-installed root CA is
/// required.
///
/// iOS 18+ may require extra provisioning entitlements for fully-local OTA
/// handoff. When the embedded provisioning profile does not authorize them,
/// ReyForge automatically uses compatibility-local mode: the signed IPA stays
/// on 127.0.0.1 while an HTTPS manifest helper performs only the manifest
/// handoff. This is the same class of fallback used by Feather.
final class LocalhostInstallManager: ObservableObject, @unchecked Sendable {
    @Published private(set) var status = "No-settings local installer ready"
    @Published private(set) var lastError: String?
    @Published private(set) var isServing = false
    @Published private(set) var endpoint = "127.0.0.1"
    @Published private(set) var activeModeText = "Ready"

    let supportsFullyLocal: Bool

    private let queue = DispatchQueue(label: "app.reyforge.local-installer", qos: .userInitiated)
    private var port = NWEndpoint.Port(rawValue: 5678)!
    private var listener: NWListener?
    private var activeIPAURL: URL?
    private var activeBundleIdentifier = ""
    private var token = ""
    private var activeHost = "127.0.0.1"
    private var activeMode: LocalInstallMode = .compatibilityLocal
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    // Replaced during the GitHub build with the current public *.backloop.dev
    // certificate/key bundle from https://backloop.dev/pack.json.
    private static let backloopP12Password = "reyforge-backloop"
    private static let backloopP12Base64 = "__BACKLOOP_P12_BASE64__"
    static let bundledBackloopExpiry = "__BACKLOOP_NOT_AFTER__"

    init() {
        supportsFullyLocal = Self.detectFullyLocalEntitlements()
    }

    deinit {
        listener?.cancel()
    }

    /// Uses fully-local trusted TLS when the provisioning profile authorizes
    /// the iOS 18+ networking entitlements; otherwise uses compatibility-local.
    func install(ipaURL: URL?, bundleIdentifier: String) {
        let mode: LocalInstallMode = supportsFullyLocal ? .fullyLocalTrustedTLS : .compatibilityLocal
        start(ipaURL: ipaURL, bundleIdentifier: bundleIdentifier, mode: mode)
    }

    /// Allows testing the completely local backloop.dev route even when the
    /// profile capability detector recommends compatibility mode.
    func tryFullyLocal(ipaURL: URL?, bundleIdentifier: String) {
        start(ipaURL: ipaURL, bundleIdentifier: bundleIdentifier, mode: .fullyLocalTrustedTLS)
    }

    func stopServer() {
        listener?.cancel()
        listener = nil
        activeIPAURL = nil
        activeBundleIdentifier = ""
        token = ""
        activeHost = "127.0.0.1"
        endBackgroundTask()
        publishServing(false)
    }

    private func start(ipaURL: URL?, bundleIdentifier: String, mode: LocalInstallMode) {
        guard let ipaURL, FileManager.default.fileExists(atPath: ipaURL.path) else {
            publishError(LocalInstallError.signedIPAMissing)
            return
        }

        stopServer()
        lastError = nil
        activeMode = mode
        port = NWEndpoint.Port(rawValue: UInt16.random(in: 4200...7900))!
        token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        activeIPAURL = ipaURL
        activeBundleIdentifier = bundleIdentifier

        do {
            let parameters: NWParameters
            switch mode {
            case .fullyLocalTrustedTLS:
                activeHost = "reyforge-\(token.prefix(12)).backloop.dev"
                activeModeText = "Fully Local · trusted backloop.dev TLS"
                status = "Starting trusted local HTTPS server…"

                let secIdentity = try Self.loadBackloopTLSIdentity()
                guard let identity = sec_identity_create(secIdentity) else {
                    throw LocalInstallError.invalidBackloopIdentity
                }
                let tls = NWProtocolTLS.Options()
                sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
                sec_protocol_options_set_local_identity(tls.securityProtocolOptions, identity)
                parameters = NWParameters(tls: tls, tcp: .init())

            case .compatibilityLocal:
                activeHost = "127.0.0.1"
                activeModeText = "Compatibility Local · IPA stays on device"
                status = "Starting compatibility localhost server…"
                parameters = .tcp
            }

            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.publishEndpoint()
                    self.publishServing(true)
                    self.publishStatus("Local install server ready")
                    self.openInstallerHandoff()
                case .failed(let error):
                    self.publishError(LocalInstallError.serverFailed(error.localizedDescription))
                    self.stopServer()
                case .cancelled:
                    self.publishServing(false)
                default:
                    break
                }
            }

            listener.start(queue: queue)
        } catch {
            publishError(error)
            stopServer()
        }
    }

    private func openInstallerHandoff() {
        guard !token.isEmpty else { return }

        switch activeMode {
        case .fullyLocalTrustedTLS:
            let manifest = "https://\(activeHost):\(port.rawValue)/\(token)/manifest.plist"
            guard let encoded = Self.strictPercentEncode(manifest),
                  let installURL = URL(string: "itms-services://?action=download-manifest&url=\(encoded)") else {
                publishError(LocalInstallError.installerURLFailed)
                return
            }
            openURLWithBackgroundTime(installURL, successStatus: "iOS installer opened · fully local trusted TLS")

        case .compatibilityLocal:
            // Opening the localhost HTML page in Safari is intentional. On
            // modern iOS this avoids requiring restricted fully-local handoff
            // entitlements while the actual IPA continues to be served only
            // from this device.
            guard let pageURL = URL(string: "http://127.0.0.1:\(port.rawValue)/\(token)/install") else {
                publishError(LocalInstallError.installerURLFailed)
                return
            }
            openURLWithBackgroundTime(pageURL, successStatus: "Safari opened local installation handoff")
        }
    }

    private func openURLWithBackgroundTime(_ url: URL, successStatus: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.beginBackgroundTask()
            UIApplication.shared.open(url, options: [:]) { accepted in
                if accepted {
                    self.status = successStatus
                } else {
                    self.publishError(LocalInstallError.installerURLFailed)
                    self.stopServer()
                }
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: queue)
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.publishError(LocalInstallError.serverFailed(error.localizedDescription))
                connection.cancel()
                return
            }

            var combined = buffer
            if let data { combined.append(data) }

            if combined.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                self.routeRequest(connection, requestData: combined)
            } else {
                self.receiveRequest(connection, buffer: combined)
            }
        }
    }

    private func routeRequest(_ connection: NWConnection, requestData: Data) {
        guard let request = String(data: requestData, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first else {
            sendSimple(connection, status: "400 Bad Request", contentType: "text/plain", body: Data("Bad Request".utf8))
            return
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendSimple(connection, status: "400 Bad Request", contentType: "text/plain", body: Data("Bad Request".utf8))
            return
        }

        let method = String(parts[0])
        guard method == "GET" || method == "HEAD" else {
            sendSimple(connection, status: "405 Method Not Allowed", contentType: "text/plain", body: Data("GET/HEAD only".utf8))
            return
        }
        let headOnly = method == "HEAD"

        let rawPath = String(parts[1])
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        let expectedPrefix = "/\(token)/"
        guard !token.isEmpty, path.hasPrefix(expectedPrefix) else {
            sendSimple(connection, status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8), headOnly: headOnly)
            return
        }

        if path == "\(expectedPrefix)manifest.plist", activeMode == .fullyLocalTrustedTLS {
            do {
                let data = try manifestData()
                sendSimple(connection, status: "200 OK", contentType: "text/xml", body: data, headOnly: headOnly)
            } catch {
                sendSimple(connection, status: "500 Internal Server Error", contentType: "text/plain", body: Data(error.localizedDescription.utf8), headOnly: headOnly)
            }
            return
        }

        if path == "\(expectedPrefix)install", activeMode == .compatibilityLocal {
            do {
                let html = try compatibilityInstallPageData()
                sendSimple(connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: html, headOnly: headOnly)
            } catch {
                sendSimple(connection, status: "500 Internal Server Error", contentType: "text/plain", body: Data(error.localizedDescription.utf8), headOnly: headOnly)
            }
            return
        }

        if path == "\(expectedPrefix)app.ipa", let ipa = activeIPAURL {
            if headOnly {
                sendFileHeaders(connection, url: ipa, contentType: "application/octet-stream")
            } else {
                sendFile(connection, url: ipa, contentType: "application/octet-stream")
            }
            return
        }

        sendSimple(connection, status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8), headOnly: headOnly)
    }

    private func manifestData() throws -> Data {
        let ipaURL = "https://\(activeHost):\(port.rawValue)/\(token)/app.ipa"
        let manifest: [String: Any] = [
            "items": [[
                "assets": [[
                    "kind": "software-package",
                    "url": ipaURL
                ]],
                "metadata": [
                    "bundle-identifier": activeBundleIdentifier,
                    "bundle-version": "1.0",
                    "kind": "software",
                    "title": "ReyForge Signed App"
                ]
            ]]
        ]
        return try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
    }

    private func compatibilityInstallPageData() throws -> Data {
        let payload = "http://127.0.0.1:\(port.rawValue)/\(token)/app.ipa"

        var manifestComponents = URLComponents(string: "https://api.palera.in/genPlist")
        manifestComponents?.queryItems = [
            URLQueryItem(name: "bundleid", value: activeBundleIdentifier),
            URLQueryItem(name: "name", value: "ReyForge Signed App"),
            URLQueryItem(name: "version", value: "1.0"),
            URLQueryItem(name: "fetchurl", value: payload)
        ]

        guard let externalManifest = manifestComponents?.url?.absoluteString,
              let encodedManifest = Self.strictPercentEncode(externalManifest) else {
            throw LocalInstallError.manifestURLFailed
        }

        let installURL = "itms-services://?action=download-manifest&url=\(encodedManifest)"
        let jsLiteralData = try JSONEncoder().encode(installURL)
        guard let jsLiteral = String(data: jsLiteralData, encoding: .utf8) else {
            throw LocalInstallError.installerURLFailed
        }

        let html = """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>ReyForge Install</title>
          </head>
          <body style="font-family:-apple-system;padding:24px;background:#111;color:#fff">
            <h2>Opening iOS Installer…</h2>
            <p>The signed IPA remains on this iPhone and is being served from localhost.</p>
            <script>window.location = \(jsLiteral);</script>
          </body>
        </html>
        """
        return Data(html.utf8)
    }

    private func sendSimple(_ connection: NWConnection, status: String, contentType: String, body: Data, headOnly: Bool = false) {
        let header = responseHeader(status: status, contentType: contentType, length: body.count)
        var packet = Data(header.utf8)
        if !headOnly { packet.append(body) }
        connection.send(content: packet, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendFileHeaders(_ connection: NWConnection, url: URL, contentType: String) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let length = (attributes[.size] as? NSNumber)?.intValue ?? 0
            let header = responseHeader(status: "200 OK", contentType: contentType, length: length)
            connection.send(content: Data(header.utf8), contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            sendSimple(connection, status: "500 Internal Server Error", contentType: "text/plain", body: Data(error.localizedDescription.utf8))
        }
    }

    private func sendFile(_ connection: NWConnection, url: URL, contentType: String) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let length = (attributes[.size] as? NSNumber)?.intValue ?? 0
            let header = responseHeader(status: "200 OK", contentType: contentType, length: length)
            let handle = try FileHandle(forReadingFrom: url)

            connection.send(content: Data(header.utf8), contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    try? handle.close()
                    self.publishError(LocalInstallError.serverFailed(error.localizedDescription))
                    connection.cancel()
                    return
                }
                self.sendNextChunk(connection, handle: handle)
            })
        } catch {
            sendSimple(connection, status: "500 Internal Server Error", contentType: "text/plain", body: Data(error.localizedDescription.utf8))
        }
    }

    private func sendNextChunk(_ connection: NWConnection, handle: FileHandle) {
        do {
            let chunk = try handle.read(upToCount: 256 * 1024) ?? Data()
            if chunk.isEmpty {
                try? handle.close()
                connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
                    connection.cancel()
                    self?.publishStatus("Signed IPA delivered to iOS installer")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                        self?.stopServer()
                    }
                })
                return
            }

            connection.send(content: chunk, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    try? handle.close()
                    self.publishError(LocalInstallError.serverFailed(error.localizedDescription))
                    connection.cancel()
                } else {
                    self.sendNextChunk(connection, handle: handle)
                }
            })
        } catch {
            try? handle.close()
            publishError(error)
            connection.cancel()
        }
    }

    private func responseHeader(status: String, contentType: String, length: Int) -> String {
        """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(length)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r
        """
    }

    private func beginBackgroundTask() {
        Task { @MainActor [weak self] in
            guard let self, self.backgroundTask == .invalid else { return }
            self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ReyForgeLocalInstall") { [weak self] in
                self?.stopServer()
            }
        }
    }

    private func endBackgroundTask() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let task = self.backgroundTask
            guard task != .invalid else { return }
            self.backgroundTask = .invalid
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    private func publishStatus(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.status = text }
    }

    private func publishServing(_ value: Bool) {
        DispatchQueue.main.async { [weak self] in self?.isServing = value }
    }

    private func publishEndpoint() {
        let value: String
        switch activeMode {
        case .fullyLocalTrustedTLS:
            value = "https://\(activeHost):\(port.rawValue)"
        case .compatibilityLocal:
            value = "http://127.0.0.1:\(port.rawValue)"
        }
        DispatchQueue.main.async { [weak self] in self?.endpoint = value }
    }

    private func publishError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.lastError = error.localizedDescription
            self?.status = "Local install failed"
        }
    }

    private static func loadBackloopTLSIdentity() throws -> SecIdentity {
        guard backloopP12Base64 != "__BACKLOOP_P12_BASE64__",
              let data = Data(base64Encoded: backloopP12Base64) else {
            throw LocalInstallError.invalidBackloopIdentity
        }
        let options = [kSecImportExportPassphrase as String: backloopP12Password] as NSDictionary
        var rawItems: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &rawItems)
        guard status == errSecSuccess,
              let items = rawItems as? [[String: Any]],
              let rawIdentity = items.first?[kSecImportItemIdentity as String] else {
            throw LocalInstallError.invalidBackloopIdentity
        }
        return rawIdentity as! SecIdentity
    }

    private static func detectFullyLocalEntitlements() -> Bool {
        let profileURL = Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")
        guard let data = try? Data(contentsOf: profileURL) else { return false }
        let text = String(decoding: data, as: UTF8.self)
        return text.contains("com.apple.developer.networking.custom-protocol") &&
               text.contains("com.apple.developer.associated-domains.mdm-managed") &&
               text.contains("com.apple.developer.associated-domains") &&
               text.contains("com.apple.developer.networking.networkextension")
    }

    private static func strictPercentEncode(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
    }
}

struct ReyForgeLocalInstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var signer: BuiltInSigningManager
    @StateObject private var installer = LocalhostInstallManager()

    var body: some View {
        NavigationStack {
            Form {
                Section("No-settings local installation") {
                    Text("ReyForge no longer installs a custom root certificate. The signed IPA remains on this iPhone and is served from loopback during installation.")
                        .font(.footnote)

                    LabeledContent("Recommended mode", value: installer.supportsFullyLocal ? "Fully Local" : "Compatibility Local")
                    LabeledContent("Manual certificate trust", value: "Not required")
                    LabeledContent("Backloop TLS valid until", value: LocalhostInstallManager.bundledBackloopExpiry)

                    if !installer.supportsFullyLocal {
                        Text("This provisioning profile does not authorize all of the extra iOS 18+ entitlements used by the fully-local handoff. ReyForge therefore uses a compatibility route: only the OTA manifest handoff uses the HTTPS helper; the IPA itself stays on 127.0.0.1.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Install signed IPA") {
                    if let signed = signer.signedIPAURL {
                        LabeledContent("Signed IPA", value: signed.lastPathComponent)
                        LabeledContent("Endpoint", value: installer.endpoint)
                        LabeledContent("Mode", value: installer.activeModeText)

                        Button {
                            installer.install(ipaURL: signed, bundleIdentifier: signer.provisionedBundleIdentifier)
                        } label: {
                            Label(installer.isServing ? "Serving to iOS Installer…" : "Install Signed IPA", systemImage: "iphone.and.arrow.forward")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(installer.isServing)

                        if !installer.supportsFullyLocal {
                            Button("Try Fully Local backloop.dev") {
                                installer.tryFullyLocal(ipaURL: signed, bundleIdentifier: signer.provisionedBundleIdentifier)
                            }
                            .disabled(installer.isServing)
                        }
                    } else {
                        Text("Sign an IPA in ReyForge first. The newest signed IPA will appear here automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Status", value: installer.status)
                    if let error = installer.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Network notes") {
                    Text("For Fully Local mode, *.backloop.dev must not be blocked by DNS/VPN filtering. It resolves back to this device and uses a public CA-signed TLS certificate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Compatibility Local uses api.palera.in only to generate the HTTPS OTA manifest. The IPA file itself is not uploaded and remains served from localhost.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Your current provisioning profile still fixes signed builds to \(signer.provisionedBundleIdentifier), so installing another build with the same App ID can replace ReyForge itself.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("Local Install")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        installer.stopServer()
                        dismiss()
                    }
                }
            }
        }
    }
}
