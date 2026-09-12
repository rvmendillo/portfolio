import Foundation

@main
struct IdentityRegression {
    static func main() throws {
        // A fixed profile must never silently become a second app's identity.
        let fixture: [String: Any] = [
            "ExpirationDate": Date(timeIntervalSince1970: 2_000_000_000),
            "Entitlements": ["application-identifier": "TEAM.app.seaweed4660.tiger8048"]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: fixture, format: .xml, options: 0)
        let wrapped = Data([0x30, 0x82, 0xff]) + data + Data([0x00, 0xff])
        let profile = try ProvisioningMetadata(data: wrapped)
        precondition(profile.appIDPattern == AppIdentity.legacyReyForge)
        do {
            try profile.validate(identifier: AppIdentity.reyForge, now: Date(timeIntervalSince1970: 1))
            fatalError("A shared fixed App ID must not authorize ReyForge's dedicated ID")
        } catch IdentityError.profileMismatch { }
        do {
            try profile.validate(identifier: AppIdentity.legacyReyForge, now: Date(timeIntervalSince1970: 2_100_000_000))
            fatalError("Expired profile accepted")
        } catch IdentityError.expiredProfile { }
        precondition(AppIdentity.matches("com.rey.app.widget", profilePattern: "com.rey.*"))
        precondition(!AppIdentity.matches("com.reyforge.app", profilePattern: "com.rey.*"))
        precondition(!AppIdentity.matches("com.rey", profilePattern: "com.rey.*"))
        for invalid in ["com..app", ".com.app", "com.app.", "com.app_name", "com.app/../../Spotify", "com.🎹"] {
            precondition(!AppIdentity.isValid(invalid), invalid)
        }
        precondition(AppIdentity.replacingPrefix("com.test.app.widget", old: "com.test.app", new: "com.rey.editor") == "com.rey.editor.widget")
        precondition(AppIdentity.replacingPrefix("org.vendor.com.test.app", old: "com.test.app", new: "com.rey.editor") == "org.vendor.com.test.app")
        let a = AppIdentity.projectIdentifier(name: "ReyForge 🎹", id: UUID())
        let b = AppIdentity.projectIdentifier(name: "ReyForge 🎹", id: UUID())
        precondition(a != b && a != AppIdentity.reyForge && AppIdentity.isValid(a))

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.rey.music", "CFBundleExecutable": "Music",
            "CFBundleDisplayName": "Music & Piano + 50% #1 🎹", "CFBundleVersion": "42"
        ]
        let identity = try IPAIdentity(info: info, fallbackName: "Wrong fallback")
        let payload = URL(string: "http://127.0.0.1:4512/token/app.ipa")!
        let handoff = try InstallRequest.handoffURL(identity: identity, payloadURL: payload)
        let outer = URLComponents(url: handoff, resolvingAgainstBaseURL: false)!
        precondition(outer.scheme == "itms-services")
        let helperURL = outer.queryItems!.first { $0.name == "url" }!.value!
        let helper = URLComponents(string: helperURL)!
        let query = Dictionary(uniqueKeysWithValues: helper.queryItems!.map { ($0.name, $0.value ?? "") })
        precondition(query["bundleid"] == identity.bundleIdentifier)
        precondition(query["name"] == identity.name)
        precondition(query["version"] == "42")
        precondition(query["fetchurl"] == payload.absoluteString)
        let record = SignedIPA(url: payload, identity: identity)
        let restored = try JSONDecoder().decode(SignedIPA.self, from: JSONEncoder().encode(record))
        precondition(restored.identity.bundleIdentifier == "com.rey.music")
        precondition(restored.identity.version == "42")

        precondition(HTTPByteRange(header: "bytes=0-99", fileSize: 200)?.length == 100)
        precondition(HTTPByteRange(header: "bytes=100-", fileSize: 200)?.start == 100)
        precondition(HTTPByteRange(header: "bytes=-20", fileSize: 200)?.start == 180)
        precondition(HTTPByteRange(header: "bytes=100-999", fileSize: 200)?.end == 199)
        for invalid in ["bytes=200-", "bytes=10-9", "bytes=-0", "bytes=0-1,3-4", "bytes=0-18446744073709551616"] {
            precondition(HTTPByteRange(header: invalid, fileSize: 200) == nil)
        }
        print("Identity, profile, manifest, persisted artifact and range regression checks passed.")
    }
}
