import Foundation

/// Identity rules shared by the editor, signer and release checks.
enum AppIdentity {
    static let reyForge = "com.rvmendillo.reyforge"
    static let legacyReyForge = "app.seaweed4660.tiger8048"

    static func isValid(_ identifier: String) -> Bool {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return parts.count >= 2 && parts.allSatisfy {
            !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    static func matches(_ identifier: String, profilePattern: String) -> Bool {
        guard isValid(identifier) else { return false }
        if profilePattern == "*" { return true }
        if profilePattern.hasSuffix(".*") {
            let prefix = String(profilePattern.dropLast())
            return identifier.hasPrefix(prefix) && identifier.count > prefix.count
        }
        return identifier == profilePattern
    }

    static func replacingPrefix(_ value: String, old: String, new: String) -> String {
        if value == old { return new }
        if value.hasPrefix(old + ".") { return new + value.dropFirst(old.count) }
        return value
    }

    static func projectIdentifier(name: String, id: UUID) -> String {
        let slug = name.lowercased().unicodeScalars.filter {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains($0)
        }.map(String.init).joined()
        let suffix = id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "com.rvmendillo.apps.\(slug.isEmpty ? "app" : String(slug.prefix(40))).\(suffix)"
    }
}

struct ProvisioningMetadata: Sendable {
    let appIDPattern: String
    let expiration: Date

    /// Reads the signed profile's embedded plist for preflight metadata only.
    /// Zsign and iOS still verify the certificate and cryptographic signature.
    init(data: Data) throws {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try PropertyListSerialization.propertyList(
                from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil
              ) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let appID = entitlements["application-identifier"] as? String,
              let dot = appID.firstIndex(of: "."),
              let expiration = plist["ExpirationDate"] as? Date else {
            throw IdentityError.invalidProfile
        }
        self.appIDPattern = String(appID[appID.index(after: dot)...])
        self.expiration = expiration
    }

    func validate(identifier: String, now: Date = Date()) throws {
        guard expiration > now else { throw IdentityError.expiredProfile }
        guard AppIdentity.matches(identifier, profilePattern: appIDPattern) else {
            throw IdentityError.profileMismatch(appIDPattern)
        }
    }
}

struct IPAIdentity: Codable, Sendable {
    let name: String
    let bundleIdentifier: String
    let version: String

    init(info: [String: Any], fallbackName: String) throws {
        guard let identifier = info["CFBundleIdentifier"] as? String,
              AppIdentity.isValid(identifier),
              let executable = info["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), executable != ".." else {
            throw IdentityError.invalidApp
        }
        self.name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String) ?? fallbackName
        self.bundleIdentifier = identifier
        self.version = (info["CFBundleVersion"] as? String)
            ?? (info["CFBundleShortVersionString"] as? String) ?? "1"
    }
}

struct SignedIPA: Codable, Sendable {
    let url: URL
    let identity: IPAIdentity
}

enum IdentityError: LocalizedError {
    case invalidProfile, expiredProfile, invalidApp, selfReplacement
    case profileMismatch(String)

    var errorDescription: String? {
        switch self {
        case .invalidProfile: return "The provisioning profile could not be read. Import a valid signing ZIP."
        case .expiredProfile: return "This provisioning profile has expired. Import a current signing ZIP."
        case .invalidApp: return "The IPA must contain one valid app with a bundle identifier and executable."
        case .selfReplacement:
            return "This identity belongs to ReyForge. Choose a different bundle ID and a profile that permits it to keep app switching separate."
        case .profileMismatch(let pattern):
            return "This profile permits \(pattern). Import a profile for the requested bundle ID, or a matching wildcard profile. Changing a name alone does not create a separate app identity."
        }
    }
}
