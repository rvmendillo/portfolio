import Foundation
import Network

private final class HTTPHarness: @unchecked Sendable {
    let listener: NWListener
    let artifact: SignedIPA
    init(artifact: SignedIPA) throws {
        self.artifact = artifact
        listener = try LocalIPAHTTP.makeListener()
    }
    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // Network.framework requires the connection handler before start().
            listener.newConnectionHandler = { [weak self] connection in
                guard let self, let port = self.listener.port else { connection.cancel(); return }
                let base = URL(string: "http://127.0.0.1:\(port.rawValue)/test-token/")!
                let context = InstallContext(artifact: self.artifact, token: "test-token", base: base)
                LocalIPAHTTP.serve(connection, context: context, finished: {})
            }
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    let base = URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/test-token/")!
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: base)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .global())
        }
    }
}

@main
struct LocalHTTPRegression {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("test.ipa")
        let bytes = Data((0..<800_000).map { UInt8($0 % 251) })
        try bytes.write(to: file)
        let identity = try IPAIdentity(info: [
            "CFBundleIdentifier": "com.test.music", "CFBundleExecutable": "Music",
            "CFBundleDisplayName": "Music & Piano", "CFBundleVersion": "27"
        ], fallbackName: "Test")
        let harness = try HTTPHarness(artifact: SignedIPA(url: file, identity: identity))
        let base = try await harness.start()
        defer { harness.listener.cancel() }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        func request(_ path: String, method: String = "GET", range: String? = nil) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: base.appendingPathComponent(path))
            request.httpMethod = method
            if let range { request.setValue(range, forHTTPHeaderField: "Range") }
            let (data, response) = try await session.data(for: request)
            return (data, response as! HTTPURLResponse)
        }
        let (full, response) = try await request("app.ipa")
        precondition(response.statusCode == 200 && full == bytes, "Streamed IPA bytes differ")
        let (head, headResponse) = try await request("app.ipa", method: "HEAD")
        precondition(head.isEmpty && headResponse.value(forHTTPHeaderField: "Content-Length") == "800000")
        let (part, partResponse) = try await request("app.ipa", range: "bytes=10000-30000")
        precondition(partResponse.statusCode == 206 && part == bytes.subdata(in: 10_000..<30_001))
        precondition(partResponse.value(forHTTPHeaderField: "Content-Range") == "bytes 10000-30000/800000")
        let (suffix, _) = try await request("app.ipa", range: "bytes=-17")
        precondition(suffix == bytes.suffix(17))
        let (_, badRange) = try await request("app.ipa", range: "bytes=800000-")
        precondition(badRange.statusCode == 416)
        let (_, wrongPath) = try await request("unknown")
        precondition(wrongPath.statusCode == 404)
        let (_, wrongMethod) = try await request("app.ipa", method: "POST")
        precondition(wrongMethod.statusCode == 405)
        let (page, pageResponse) = try await request("install")
        precondition(pageResponse.statusCode == 200 && String(decoding: page, as: UTF8.self).contains("itms-services"))
        print("Loopback integration passed: full stream, HEAD, ranges, handoff page, and error responses.")
    }
}
