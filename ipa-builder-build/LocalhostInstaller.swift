import Foundation
import SwiftUI
import Network
import UIKit

@MainActor
final class LocalhostInstallManager: ObservableObject {
    @Published private(set) var status = "Ready to install"
    @Published private(set) var lastError: String?
    @Published private(set) var isServing = false
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var sessionID = UUID()
    private var context: InstallContext?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func install(_ artifact: SignedIPA) {
        guard !isServing else { return }
        guard FileManager.default.fileExists(atPath: artifact.url.path) else {
            lastError = "The signed file is missing. Sign the IPA again."; return
        }
        guard artifact.identity.bundleIdentifier != Bundle.main.bundleIdentifier,
              artifact.identity.bundleIdentifier != AppIdentity.legacyReyForge else {
            lastError = IdentityError.selfReplacement.localizedDescription; return
        }
        stopServer()
        lastError = nil
        status = "Starting local installer…"
        isServing = true
        let id = UUID(), token = UUID().uuidString.lowercased()
        sessionID = id
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let server = try NWListener(using: parameters, on: .any)
            listener = server
            server.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.sessionID == id,
                          let context = self.context, self.connections.count < 32 else {
                        connection.cancel(); return
                    }
                    let key = ObjectIdentifier(connection)
                    self.connections[key] = connection
                    LocalIPAHTTP.serve(connection, context: context) { [weak self] in
                        Task { @MainActor in self?.connections.removeValue(forKey: key) }
                    }
                }
            }
            server.stateUpdateHandler = { [weak self, weak server] state in
                Task { @MainActor in
                    guard let self, self.sessionID == id else { return }
                    switch state {
                    case .ready:
                        guard let port = server?.port,
                              let base = URL(string: "http://127.0.0.1:\(port.rawValue)/\(token)/") else {
                            self.fail("Could not create the local installer address."); return
                        }
                        self.context = InstallContext(artifact: artifact, token: token, base: base)
                        self.openHandoff(base.appendingPathComponent("install"), session: id)
                    case .failed(let error): self.fail(error.localizedDescription)
                    default: break
                    }
                }
            }
            server.start(queue: .main)
        } catch { fail(error.localizedDescription) }
    }
    func stopServer() {
        sessionID = UUID()
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        context = nil
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        isServing = false
        status = "Local installer stopped"
    }
    private func fail(_ message: String) {
        stopServer()
        lastError = message
        status = "Installation handoff failed"
    }
    private func openHandoff(_ url: URL, session: UUID) {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ReyForge IPA download") { [weak self] in
            Task { @MainActor in
                self?.stopServer()
                self?.status = "iOS paused the installer. Return to ReyForge and retry if needed."
            }
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] accepted in
            Task { @MainActor in
                guard let self, self.sessionID == session else { return }
                if accepted { self.status = "Installer opened. Confirm the installation in iOS." }
                else { self.fail("iOS did not open the installation page. You can export the signed IPA instead.") }
            }
        }
    }
}

private struct InstallContext: Sendable {
    let artifact: SignedIPA
    let token: String
    let base: URL
}

private enum LocalIPAHTTP {
    static func serve(_ connection: NWConnection, context: InstallContext, finished: @escaping @Sendable () -> Void) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed: connection.cancel()
            case .cancelled: finished()
            default: break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receive(connection, context: context, buffer: Data())
    }
    private static func receive(_ connection: NWConnection, context: InstallContext, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, complete, error in
            var request = buffer
            if let data { request.append(data) }
            if request.count > 16_384 { respond(connection, status: "431 Request Header Fields Too Large") }
            else if request.range(of: Data("\r\n\r\n".utf8)) != nil { handle(connection, context: context, request: request) }
            else if complete || error != nil { connection.cancel() }
            else { receive(connection, context: context, buffer: request) }
        }
    }
    private static func handle(_ connection: NWConnection, context: InstallContext, request: Data) {
        let lines = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count == 3 else { respond(connection, status: "400 Bad Request"); return }
        let method = String(first[0]), path = String(first[1])
        guard method == "GET" || method == "HEAD" else {
            respond(connection, status: "405 Method Not Allowed", extra: "Allow: GET, HEAD\r\n"); return
        }
        let head = method == "HEAD", prefix = "/\(context.token)/"
        do {
            if path == prefix + "install" {
                let data = try InstallRequest.page(identity: context.artifact.identity, payloadURL: context.base.appendingPathComponent("app.ipa"))
                respond(connection, status: "200 OK", type: "text/html; charset=utf-8", body: data, head: head)
            } else if path == prefix + "app.ipa" {
                let attrs = try FileManager.default.attributesOfItem(atPath: context.artifact.url.path)
                guard let size = (attrs[.size] as? NSNumber)?.uint64Value, size > 0 else {
                    respond(connection, status: "404 Not Found"); return
                }
                let ranges = lines.dropFirst().compactMap { line -> String? in
                    guard let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == "range" else { return nil }
                    return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                var start: UInt64 = 0, length = size, status = "200 OK"
                var extra = "Accept-Ranges: bytes\r\n"
                if let value = ranges.first {
                    guard ranges.count == 1, let range = HTTPByteRange(header: value, fileSize: size) else {
                        respond(connection, status: "416 Range Not Satisfiable", extra: "Content-Range: bytes */\(size)\r\n"); return
                    }
                    start = range.start; length = range.length; status = "206 Partial Content"
                    extra += "Content-Range: bytes \(range.start)-\(range.end)/\(size)\r\n"
                }
                let header = headers(status: status, type: "application/octet-stream", length: length, extra: extra)
                if head { connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in connection.cancel() }) }
                else {
                    let stream = try IPAFileStream(url: context.artifact.url, offset: start, length: length)
                    connection.send(content: Data(header.utf8), completion: .contentProcessed { error in
                        if error != nil { stream.close(); connection.cancel() }
                        else { stream.send(to: connection) }
                    })
                }
            } else { respond(connection, status: "404 Not Found") }
        } catch { respond(connection, status: "500 Internal Server Error") }
    }
    private static func headers(status: String, type: String, length: UInt64, extra: String = "") -> String {
        "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(length)\r\nCache-Control: no-store\r\nConnection: close\r\n\(extra)\r\n"
    }
    private static func respond(_ connection: NWConnection, status: String, type: String = "text/plain", body: Data = Data(), head: Bool = false, extra: String = "") {
        var data = Data(headers(status: status, type: type, length: UInt64(body.count), extra: extra).utf8)
        if !head { data.append(body) }
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// Each stream has only one in-flight send and a serial file cursor.
private final class IPAFileStream: @unchecked Sendable {
    private let file: FileHandle
    private var remaining: UInt64
    init(url: URL, offset: UInt64, length: UInt64) throws {
        file = try FileHandle(forReadingFrom: url)
        remaining = length
        try file.seek(toOffset: offset)
    }
    deinit { try? file.close() }
    func close() { try? file.close() }
    func send(to connection: NWConnection) {
        guard remaining > 0 else { close(); connection.cancel(); return }
        do {
            guard let data = try file.read(upToCount: Int(min(remaining, 256 * 1024))), !data.isEmpty else {
                close(); connection.cancel(); return
            }
            remaining -= UInt64(data.count)
            connection.send(content: data, completion: .contentProcessed { [self] error in
                if error != nil { close(); connection.cancel() }
                else { send(to: connection) }
            })
        } catch { close(); connection.cancel() }
    }
}

struct ReyForgeLocalInstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var signer: BuiltInSigningManager
    @StateObject private var installer = LocalhostInstallManager()
    var body: some View {
        NavigationStack {
            Form {
                Section("Install signed IPA") {
                    if let artifact = signer.signedArtifact {
                        LabeledContent("App", value: artifact.identity.name)
                        LabeledContent("Version", value: artifact.identity.version)
                        LabeledContent("Bundle ID", value: artifact.identity.bundleIdentifier)
                        Button { installer.install(artifact) } label: {
                            Label(installer.isServing ? "Serving IPA…" : "Install Signed IPA", systemImage: "iphone.and.arrow.forward")
                        }
                        .disabled(installer.isServing)
                        ShareLink(item: artifact.url) { Label("Export Signed IPA", systemImage: "square.and.arrow.up") }
                    } else { Text("Sign an IPA first. Its verified identity will appear here.") }
                    LabeledContent("Status", value: installer.status)
                    if let error = installer.lastError { Text(error).foregroundStyle(.red) }
                    if installer.isServing { Button("Stop Installer") { installer.stopServer() } }
                }
                Section {
                    Text("The IPA stays on this iPhone. The HTTPS manifest helper receives the app name, bundle ID, version, and a temporary localhost link.")
                    Text("No custom root certificate or manual certificate trust is required.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Local Install")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .onDisappear { installer.stopServer() }
    }
}
