import Foundation
import SwiftUI
import Network
import Security
import UIKit

private enum LocalhostInstallError: LocalizedError {
    case invalidBundledIdentity
    case signedIPAMissing
    case serverFailed(String)
    case installerURLFailed

    var errorDescription: String? {
        switch self {
        case .invalidBundledIdentity:
            return "ReyForge could not load its localhost TLS identity."
        case .signedIPAMissing:
            return "Sign an IPA first."
        case .serverFailed(let detail):
            return "Local HTTPS server failed: \(detail)"
        case .installerURLFailed:
            return "iOS did not accept the local installation URL."
        }
    }
}

/// Hosts a signed IPA only on 127.0.0.1 over TLS, generates an OTA manifest,
/// and hands that manifest to the iOS system installer through itms-services.
///
/// The included leaf certificate is valid only for localhost / 127.0.0.1 / ::1.
/// Its signing root's private key is not included in ReyForge. The public root
/// certificate is exposed as a configuration profile for one-time local trust.
final class LocalhostInstallManager: ObservableObject, @unchecked Sendable {
    @Published private(set) var status = "Localhost installer ready"
    @Published private(set) var lastError: String?
    @Published private(set) var isServing = false
    @Published private(set) var trustProfileURL: URL?

    private let queue = DispatchQueue(label: "app.reyforge.localhost-installer", qos: .userInitiated)
    private let port = NWEndpoint.Port(rawValue: 8443)!
    private var listener: NWListener?
    private var activeIPAURL: URL?
    private var activeBundleIdentifier = ""
    private var token = ""
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private static let tlsPassword = "reyforge-local"

    // PKCS#12 contains only the localhost leaf private key/certificate plus its public chain.
    private static let localhostP12Base64 = "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"

    // DER-encoded public root certificate only. The CA private key is intentionally not shipped.
    private static let rootCertificateBase64 = "MIIDhDCCAmygAwIBAgIUKcC0mX+QQhxS8XUHymBKdyL0y7AwDQYJKoZIhvcNAQELBQAwSDEjMCEGA1UEAwwaUmV5Rm9yZ2UgTG9jYWxob3N0IFJvb3QgQ0ExITAfBgNVBAoMGFJleUZvcmdlIExvY2FsIEluc3RhbGxlcjAeFw0yNjA5MDQxMDQxMzVaFw0zNjA5MDExMDQxMzVaMEgxIzAhBgNVBAMMGlJleUZvcmdlIExvY2FsaG9zdCBSb290IENBMSEwHwYDVQQKDBhSZXlGb3JnZSBMb2NhbCBJbnN0YWxsZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQClwQimwOK7aeeEr1TTATqpI0WAmCpHCie1d5XBRqtzVlaWb/JfNE+EN5uuYnkQplhlsMziNfrhVExoDWDWd6FDaGtFZ8Br9pod8UHN+6Ssti78fcNiBLQ6y/WkaLpOGqeC+C2M6uA2UR4WbABTiTmHmEAts1WFt51Ckd9TZxt5LMn0bJLMbIRxmNEonGwTJBIA2DKdixUFJGPj7SYTMSZ6ky4Kln7Pi979YHreR6YQLvvqQNtMfHidOhDVURbrU2DJRj+i1Dj1bdXEJYLvOxvcg0d5V9UStFctSxjQiRHGxU48lHkbPjvAOwbEqEo8jWDVsRUoIafvND9KZTyQOVlHAgMBAAGjZjBkMB0GA1UdDgQWBBROa7nQnx7CuOGQBObme+g95ppO1jAfBgNVHSMEGDAWgBROa7nQnx7CuOGQBObme+g95ppO1jASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBBjANBgkqhkiG9w0BAQsFAAOCAQEAQC/ikguxzX0KFk0JtYnFZn57jNIzRUk+TlE4DIbcl9tzwPXql+8ozuHYhIL7CDQT/46bWVkS81AP1I6h+sKahzgovsn6LEaM1WFgfUMz5R7unBK3CUIqjDpvfukWjhHhNG9I9wQY5uFeVuFi8pcfJW0T1TqEyoOmf07VzLN0X/iNrkVHhyNp5eYcU8cDVmIqbhkjv3/lWSTsxNr5LYf1n5CKgrgdPdLZelz7mqXv0/tigYd6J6RgTgFk6kr+LC7S4gfTxdOAhjumyitqVQBxcm3RoJcaVXr+VqtwOfIkvOsWTZyIFwVEcxppqNlRhQr1fDncwGKtDf8YxLyDKdCYXA=="

    init() {
        do {
            trustProfileURL = try Self.writeTrustProfile()
        } catch {
            lastError = error.localizedDescription
        }
    }

    deinit {
        listener?.cancel()
    }

    func install(ipaURL: URL?, bundleIdentifier: String) {
        guard let ipaURL, FileManager.default.fileExists(atPath: ipaURL.path) else {
            publishError(LocalhostInstallError.signedIPAMissing)
            return
        }

        stopServer()
        lastError = nil
        status = "Starting https://127.0.0.1:8443…"

        do {
            let secIdentity = try Self.loadTLSIdentity()
            guard let identity = sec_identity_create(secIdentity) else {
                throw LocalhostInstallError.invalidBundledIdentity
            }

            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, identity)

            let parameters = NWParameters(tls: tls, tcp: .init())
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters)
            self.listener = listener
            self.activeIPAURL = ipaURL
            self.activeBundleIdentifier = bundleIdentifier
            self.token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.publishStatus("Local HTTPS server ready")
                    self.publishServing(true)
                    self.openSystemInstaller()
                case .failed(let error):
                    self.publishError(LocalhostInstallError.serverFailed(error.localizedDescription))
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

    func stopServer() {
        listener?.cancel()
        listener = nil
        activeIPAURL = nil
        activeBundleIdentifier = ""
        token = ""
        endBackgroundTask()
        publishServing(false)
    }

    private func openSystemInstaller() {
        guard !token.isEmpty else { return }
        let manifest = "https://127.0.0.1:\(port.rawValue)/\(token)/manifest.plist"
        guard let encoded = manifest.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let installURL = URL(string: "itms-services://?action=download-manifest&url=\(encoded)") else {
            publishError(LocalhostInstallError.installerURLFailed)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.beginBackgroundTask()
            UIApplication.shared.open(installURL, options: [:]) { accepted in
                if accepted {
                    self.status = "iOS installer opened · serving signed IPA from localhost"
                } else {
                    self.publishError(LocalhostInstallError.installerURLFailed)
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
                self.publishError(LocalhostInstallError.serverFailed(error.localizedDescription))
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
        guard parts.count >= 2, parts[0] == "GET" else {
            sendSimple(connection, status: "405 Method Not Allowed", contentType: "text/plain", body: Data("GET only".utf8))
            return
        }

        let path = String(parts[1])
        let expectedPrefix = "/\(token)/"
        guard !token.isEmpty, path.hasPrefix(expectedPrefix) else {
            sendSimple(connection, status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8))
            return
        }

        if path == "\(expectedPrefix)manifest.plist" {
            do {
                let data = try manifestData()
                sendSimple(connection, status: "200 OK", contentType: "text/xml", body: data)
            } catch {
                sendSimple(connection, status: "500 Internal Server Error", contentType: "text/plain", body: Data(error.localizedDescription.utf8))
            }
            return
        }

        if path == "\(expectedPrefix)app.ipa", let ipa = activeIPAURL {
            sendFile(connection, url: ipa, contentType: "application/octet-stream")
            return
        }

        sendSimple(connection, status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8))
    }

    private func manifestData() throws -> Data {
        let ipaURL = "https://127.0.0.1:\(port.rawValue)/\(token)/app.ipa"
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

    private func sendSimple(_ connection: NWConnection, status: String, contentType: String, body: Data) {
        let header = responseHeader(status: status, contentType: contentType, length: body.count)
        var packet = Data(header.utf8)
        packet.append(body)
        connection.send(content: packet, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
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
                    self.publishError(LocalhostInstallError.serverFailed(error.localizedDescription))
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                        self?.stopServer()
                    }
                })
                return
            }

            connection.send(content: chunk, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    try? handle.close()
                    self.publishError(LocalhostInstallError.serverFailed(error.localizedDescription))
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
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ReyForgeLocalInstall") { [weak self] in
            self?.stopServer()
        }
    }

    private func endBackgroundTask() {
        let task = backgroundTask
        guard task != .invalid else { return }
        backgroundTask = .invalid
        DispatchQueue.main.async {
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    private func publishStatus(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.status = text }
    }

    private func publishServing(_ value: Bool) {
        DispatchQueue.main.async { [weak self] in self?.isServing = value }
    }

    private func publishError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.lastError = error.localizedDescription
            self?.status = "Local install failed"
        }
    }

    private static func loadTLSIdentity() throws -> SecIdentity {
        guard let data = Data(base64Encoded: localhostP12Base64) else {
            throw LocalhostInstallError.invalidBundledIdentity
        }
        let options = [kSecImportExportPassphrase as String: tlsPassword] as NSDictionary
        var rawItems: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &rawItems)
        guard status == errSecSuccess,
              let items = rawItems as? [[String: Any]],
              let identity = items.first?[kSecImportItemIdentity as String] as? SecIdentity else {
            throw LocalhostInstallError.invalidBundledIdentity
        }
        return identity
    }

    private static func writeTrustProfile() throws -> URL {
        guard let certificate = Data(base64Encoded: rootCertificateBase64) else {
            throw LocalhostInstallError.invalidBundledIdentity
        }

        let certificatePayload: [String: Any] = [
            "PayloadCertificateFileName": "ReyForge Localhost Root CA.cer",
            "PayloadContent": certificate,
            "PayloadDescription": "Trusts only ReyForge's localhost HTTPS installation certificate chain.",
            "PayloadDisplayName": "ReyForge Localhost Root CA",
            "PayloadIdentifier": "app.rvmendillo.reyforge.localhost.root.certificate",
            "PayloadType": "com.apple.security.root",
            "PayloadUUID": "7A9A0557-41AE-4719-8A0D-9DA085C8DD41",
            "PayloadVersion": 1
        ]

        let profile: [String: Any] = [
            "PayloadContent": [certificatePayload],
            "PayloadDescription": "One-time certificate trust for ReyForge localhost IPA installation.",
            "PayloadDisplayName": "ReyForge Localhost Installer Trust",
            "PayloadIdentifier": "app.rvmendillo.reyforge.localhost.root.profile",
            "PayloadOrganization": "ReyForge",
            "PayloadRemovalDisallowed": false,
            "PayloadType": "Configuration",
            "PayloadUUID": "30670DE1-3F70-4A0A-A86A-78A21F13BB54",
            "PayloadVersion": 1
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalInstaller", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ReyForge-Localhost-Trust.mobileconfig")
        try data.write(to: url, options: .atomic)
        return url
    }
}

struct ReyForgeLocalInstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var signer: BuiltInSigningManager
    @StateObject private var installer = LocalhostInstallManager()

    var body: some View {
        NavigationStack {
            Form {
                Section("One-time localhost trust") {
                    Text("iOS requires the OTA manifest and IPA to come from HTTPS with a certificate the device trusts. ReyForge therefore uses https://127.0.0.1:8443 and a localhost-only certificate.")
                        .font(.footnote)

                    if let profile = installer.trustProfileURL {
                        ShareLink(item: profile) {
                            Label("Open / Share Trust Profile", systemImage: "checkmark.shield")
                        }
                    }

                    Text("Install the profile in Settings → General → VPN & Device Management. Then enable full trust for ‘ReyForge Localhost Root CA’ in Settings → General → About → Certificate Trust Settings. This is required once per device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Direct signed IPA install") {
                    if let signed = signer.signedIPAURL {
                        LabeledContent("Signed IPA", value: signed.lastPathComponent)
                        LabeledContent("Endpoint", value: "https://127.0.0.1:8443")

                        Button {
                            installer.install(ipaURL: signed, bundleIdentifier: signer.provisionedBundleIdentifier)
                        } label: {
                            Label(installer.isServing ? "Serving to iOS Installer…" : "Install Signed IPA from Localhost", systemImage: "iphone.and.arrow.forward")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(installer.isServing)
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

                Section("Important") {
                    Text("This uses Apple's OTA manifest handoff, not a private MobileInstallation API. The local HTTPS server runs only during installation and uses a random unguessable path. The CA private key is not included in ReyForge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Your current provisioning profile still forces installed builds to \(signer.provisionedBundleIdentifier), so another build with the same App ID can replace ReyForge itself.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("Localhost Install")
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
