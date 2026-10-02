import Foundation
import Security

enum HeaderVault {
    private static func query(_ id: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                               kSecAttrService as String: "ReyWidgets.APIHeaders", kSecAttrAccount as String: id]
        if let group = Bundle.main.object(forInfoDictionaryKey: "RWKeychainGroup") as? String, !group.isEmpty {
            q[kSecAttrAccessGroup as String] = group
        }
        return q
    }
    static func save(_ headers: [String: String], id: String) throws {
        let data = try JSONEncoder().encode(headers)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var q = query(id)
        let status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            q.merge(attributes) { _, new in new }
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else {
                throw StudioError.message("Could not save API headers. Check shared Keychain signing.")
            }
        } else if status != errSecSuccess { throw StudioError.message("Could not update API headers (\(status)).") }
    }
    static func read(_ id: String) throws -> [String: String] {
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data = result as? Data else {
            throw StudioError.message("API headers are unavailable. Unlock the device and check Keychain sharing.")
        }
        return try JSONDecoder().decode([String: String].self, from: data)
    }
    static func delete(_ id: String) { SecItemDelete(query(id) as CFDictionary) }
}

// Redirects are rejected so credentials cannot be forwarded to another host.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum APIClient {
    static func fetch(_ doc: WidgetDocument) async throws -> Data {
        let url = try doc.api.validatedURL()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = doc.api.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if doc.api.method == "POST" {
            request.httpBody = doc.api.body.data(using: .utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in try HeaderVault.read(doc.api.credentialID) {
            guard key.range(of: #"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$"#, options: .regularExpression) != nil,
                  !value.contains("\r"), !value.contains("\n") else {
                throw StudioError.message("A request header contains invalid characters.")
            }
            request.setValue(value, forHTTPHeaderField: key)
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 20
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw StudioError.message("No HTTP response.") }
        guard (200...299).contains(http.statusCode) else {
            throw StudioError.message("API returned HTTP \(http.statusCode). Redirects are disabled; enter the final endpoint URL.")
        }
        guard response.expectedContentLength <= 1_000_000 else { throw StudioError.message("API response exceeds 1 MB.") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_000_000 else { throw StudioError.message("API response exceeds 1 MB.") }
            data.append(byte)
        }
        _ = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        return data
    }
}
