import Foundation
import SwiftUI
import Security
import UniformTypeIdentifiers
import ZIPFoundation
import ZsignSwift

private enum SigningPasswordStore {
    static let service = "com.rvmendillo.reyforge.signing"
    static let account = "p12-password"

    static func save(_ value: String) throws {
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum ReyForgeSigningError: LocalizedError {
    case signingAssetsMissing
    case invalidArchive
    case invalidBundleIdentifier
    case noSigningPair
    case signFailed(String)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .signingAssetsMissing:
            return "Signing assets are not configured."
        case .invalidArchive:
            return "The IPA or signing bundle could not be opened."
        case .invalidBundleIdentifier:
            return "Enter a valid bundle identifier, for example com.example.myapp."
        case .noSigningPair:
            return "No matching .p12 and .mobileprovision pair was found."
        case .signFailed(let detail):
            return detail.isEmpty ? "Local Zsign signing failed." : "Local Zsign signing failed: \(detail)"
        case .validationFailed(let detail):
            return "Signed IPA validation failed: \(detail)"
        }
    }
}

private struct IPAIdentity: Sendable {
    let name: String
    let bundleIdentifier: String
}

@MainActor
final class BuiltInSigningManager: ObservableObject {
    @Published var status = "Checking signing assets…"
    @Published var isSigning = false
    @Published var isImporting = false
    @Published var isImportingIPA = false
    @Published var signedIPAURL: URL?
    @Published var importedIPAURL: URL?
    @Published var lastError: String?
    @Published var diagnostic = ""
    @Published var targetAppName = "My App"
    @Published var targetBundleIdentifier = "com.rvmendillo.myapp"
    @Published private(set) var signedBundleIdentifier: String?
    @Published private(set) var signedAppName: String?

    /// The App ID carried by the built-in provisioning profile. This is shown
    /// for diagnostics only. ReyForge no longer forces signed apps to use it.
    let profileBundleIdentifier = "app.seaweed4660.tiger8048"
    let profileExpirationText = "March 2027"

    /// Kept for LocalhostInstaller compatibility. It now returns the bundle ID
    /// of the app that was actually signed, rather than forcibly returning the
    /// provisioning profile's App ID.
    var provisionedBundleIdentifier: String {
        if let signedBundleIdentifier, !signedBundleIdentifier.isEmpty {
            return signedBundleIdentifier
        }
        let requested = targetBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return requested.isEmpty ? profileBundleIdentifier : requested
    }

    private let builtInPassword = "1"
    private let fileManager = FileManager.default

    init() {
        installBundledAssetsIfNeeded()
        status = isConfigured ? "Built-in signer ready" : "Import signing bundle"
    }

    var isConfigured: Bool {
        fileManager.fileExists(atPath: p12URL.path) &&
        fileManager.fileExists(atPath: provisionURL.path)
    }

    func setTargetIdentity(name: String, bundleIdentifier: String) {
        targetAppName = name
        targetBundleIdentifier = bundleIdentifier
        signedBundleIdentifier = nil
        signedAppName = nil
    }

    func importSigningBundle(_ url: URL) async {
        isImporting = true
        lastError = nil
        diagnostic = "Opening signing bundle"
        status = "Importing signing bundle…"

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let destination = vaultDirectory
            try await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                let temp = fm.temporaryDirectory.appendingPathComponent("ReyForgeSigningImport-\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: temp, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: temp) }

                guard url.pathExtension.lowercased() == "zip" else {
                    throw ReyForgeSigningError.invalidArchive
                }
                try fm.unzipItem(at: url, to: temp)

                let enumerator = fm.enumerator(at: temp, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                let files = (enumerator?.allObjects as? [URL]) ?? []
                let p12 = files.first { $0.pathExtension.lowercased() == "p12" && $0.lastPathComponent.lowercased().contains("distribution") }
                    ?? files.first { $0.pathExtension.lowercased() == "p12" }
                let provision = files.first { $0.pathExtension.lowercased() == "mobileprovision" && $0.lastPathComponent.lowercased().contains("distribution") }
                    ?? files.first { $0.pathExtension.lowercased() == "mobileprovision" }

                guard let p12, let provision else { throw ReyForgeSigningError.noSigningPair }

                try? fm.removeItem(at: destination)
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                try fm.copyItem(at: p12, to: destination.appendingPathComponent("distribution.p12"))
                try fm.copyItem(at: provision, to: destination.appendingPathComponent("distribution.mobileprovision"))
            }.value

            try? SigningPasswordStore.save(builtInPassword)
            diagnostic = "P12 and provisioning profile imported"
            status = "Built-in signer ready"
            objectWillChange.send()
        } catch {
            lastError = error.localizedDescription
            diagnostic = "Signing bundle import failed"
            status = "Signing import failed"
        }

        isImporting = false
    }

    func importIPA(_ url: URL) async {
        isImportingIPA = true
        lastError = nil
        status = "Importing IPA…"
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let result = try await Task.detached(priority: .userInitiated) { () -> (URL, IPAIdentity?) in
                let fm = FileManager.default
                let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("SigningInputs", isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let cleanName = url.lastPathComponent.lowercased().hasSuffix(".ipa") ? url.lastPathComponent : "Imported.ipa"
                let target = dir.appendingPathComponent(cleanName)
                try? fm.removeItem(at: target)
                try fm.copyItem(at: url, to: target)
                return (target, try? Self.inspectIPA(target))
            }.value

            importedIPAURL = result.0
            if let identity = result.1 {
                targetAppName = identity.name
                targetBundleIdentifier = identity.bundleIdentifier
            }
            signedBundleIdentifier = nil
            signedAppName = nil
            diagnostic = "Imported \(result.0.lastPathComponent)"
            status = "IPA ready to sign"
        } catch {
            lastError = error.localizedDescription
            status = "IPA import failed"
        }
        isImportingIPA = false
    }

    func sign(ipaURL: URL, widgetEnabled: Bool) async {
        guard isConfigured else {
            lastError = ReyForgeSigningError.signingAssetsMissing.localizedDescription
            return
        }

        let identifier = targetBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidBundleIdentifier(identifier) else {
            lastError = ReyForgeSigningError.invalidBundleIdentifier.localizedDescription
            return
        }
        let requestedName = targetAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        let appName = requestedName.isEmpty ? "Signed App" : requestedName

        isSigning = true
        signedIPAURL = nil
        signedBundleIdentifier = nil
        signedAppName = nil
        lastError = nil
        diagnostic = widgetEnabled
            ? "Preparing \(ipaURL.lastPathComponent) and rewriting app/extension identifiers"
            : "Preparing \(ipaURL.lastPathComponent) with custom identity"
        status = "Signing IPA on device…"

        do {
            let p12 = p12URL
            let profile = provisionURL
            let password = SigningPasswordStore.load() ?? builtInPassword
            let output = try await Task.detached(priority: .userInitiated) {
                try Self.signSynchronously(
                    ipaURL: ipaURL,
                    p12URL: p12,
                    provisionURL: profile,
                    password: password,
                    bundleIdentifier: identifier,
                    appName: appName
                )
            }.value
            signedIPAURL = output
            signedBundleIdentifier = identifier
            signedAppName = appName
            diagnostic = "Signed as \(appName) · \(identifier)"
            status = "Signed IPA ready"
        } catch {
            lastError = error.localizedDescription
            diagnostic = "Runtime signer returned an error"
            status = "Signing failed"
        }

        isSigning = false
    }

    func forgetAssets() {
        try? fileManager.removeItem(at: vaultDirectory)
        SigningPasswordStore.delete()
        signedIPAURL = nil
        signedBundleIdentifier = nil
        signedAppName = nil
        status = "Signing assets removed"
        objectWillChange.send()
    }

    private func installBundledAssetsIfNeeded() {
        guard !isConfigured,
              let bundledP12 = Bundle.main.url(forResource: "distribution", withExtension: "p12", subdirectory: "BuiltInSigning"),
              let bundledProvision = Bundle.main.url(forResource: "distribution", withExtension: "mobileprovision", subdirectory: "BuiltInSigning")
        else { return }

        do {
            try fileManager.createDirectory(at: vaultDirectory, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: p12URL)
            try? fileManager.removeItem(at: provisionURL)
            try fileManager.copyItem(at: bundledP12, to: p12URL)
            try fileManager.copyItem(at: bundledProvision, to: provisionURL)
            try? SigningPasswordStore.save(builtInPassword)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private var vaultDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SigningVault", isDirectory: true)
    }

    private var p12URL: URL { vaultDirectory.appendingPathComponent("distribution.p12") }
    private var provisionURL: URL { vaultDirectory.appendingPathComponent("distribution.mobileprovision") }

    nonisolated private static func inspectIPA(_ ipaURL: URL) throws -> IPAIdentity {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ReyForgeInspect-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try fm.unzipItem(at: ipaURL, to: root)
        let payload = root.appendingPathComponent("Payload", isDirectory: true)
        let items = try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
        guard let appURL = items.first(where: { $0.pathExtension.lowercased() == "app" }),
              let info = NSDictionary(contentsOf: appURL.appendingPathComponent("Info.plist")),
              let identifier = info["CFBundleIdentifier"] as? String else {
            throw ReyForgeSigningError.invalidArchive
        }
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        return IPAIdentity(name: name, bundleIdentifier: identifier)
    }

    nonisolated private static func isValidBundleIdentifier(_ identifier: String) -> Bool {
        guard identifier.contains("."), !identifier.hasPrefix("."), !identifier.hasSuffix(".") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
        return !identifier.isEmpty && identifier.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    nonisolated private static func signSynchronously(
        ipaURL: URL,
        p12URL: URL,
        provisionURL: URL,
        password: String,
        bundleIdentifier: String,
        appName: String
    ) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: ipaURL.path), fm.fileExists(atPath: p12URL.path), fm.fileExists(atPath: provisionURL.path) else {
            throw ReyForgeSigningError.signingAssetsMissing
        }

        let root = fm.temporaryDirectory.appendingPathComponent("ReyForgeSign-\(UUID().uuidString)", isDirectory: true)
        let extract = root.appendingPathComponent("Extracted", isDirectory: true)
        try fm.createDirectory(at: extract, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try fm.unzipItem(at: ipaURL, to: extract)
        let payload = extract.appendingPathComponent("Payload", isDirectory: true)
        let payloadItems = try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        guard let appURL = payloadItems.first(where: { $0.pathExtension.lowercased() == "app" }) else {
            throw ReyForgeSigningError.invalidArchive
        }

        let infoURL = appURL.appendingPathComponent("Info.plist")
        guard let originalInfo = NSDictionary(contentsOf: infoURL),
              let oldIdentifier = originalInfo["CFBundleIdentifier"] as? String,
              !oldIdentifier.isEmpty else {
            throw ReyForgeSigningError.invalidArchive
        }

        try rewriteMainIdentity(
            appURL: appURL,
            oldIdentifier: oldIdentifier,
            newIdentifier: bundleIdentifier,
            appName: appName
        )
        try rewriteNestedBundleIdentifiers(
            inside: appURL,
            oldIdentifier: oldIdentifier,
            newIdentifier: bundleIdentifier
        )

        // Remove stale signatures and stale embedded profile before Zsign.
        try? fm.removeItem(at: appURL.appendingPathComponent("_CodeSignature", isDirectory: true))
        let embeddedProvision = appURL.appendingPathComponent("embedded.mobileprovision")
        try? fm.removeItem(at: embeddedProvision)
        try fm.copyItem(at: provisionURL, to: embeddedProvision)

        var callbackSucceeded: Bool?
        var callbackErrorText = ""
        let returned = Zsign.sign(
            appPath: appURL.path,
            provisionPath: provisionURL.path,
            p12Path: p12URL.path,
            p12Password: password,
            entitlementsPath: "",
            customIdentifier: bundleIdentifier,
            customName: appName,
            customVersion: "",
            adhoc: false,
            removeProvision: false,
            completion: { success, error in
                callbackSucceeded = success
                callbackErrorText = error?.localizedDescription ?? ""
            }
        )

        guard returned, callbackSucceeded != false else {
            throw ReyForgeSigningError.signFailed(callbackErrorText)
        }

        guard fm.fileExists(atPath: embeddedProvision.path) else {
            throw ReyForgeSigningError.validationFailed("embedded.mobileprovision is missing")
        }

        guard let info = NSDictionary(contentsOf: infoURL),
              let actualIdentifier = info["CFBundleIdentifier"] as? String,
              actualIdentifier == bundleIdentifier else {
            throw ReyForgeSigningError.validationFailed("bundle identifier did not remain \(bundleIdentifier)")
        }

        let actualName = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? ""
        guard actualName == appName else {
            throw ReyForgeSigningError.validationFailed("app name did not remain \(appName)")
        }

        guard let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty else {
            throw ReyForgeSigningError.validationFailed("CFBundleExecutable is missing")
        }
        let executableURL = appURL.appendingPathComponent(executable)
        guard fm.fileExists(atPath: executableURL.path), Zsign.checkSigned(appExecutable: executableURL.path) else {
            throw ReyForgeSigningError.validationFailed("main executable signature check failed")
        }

        let builds = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SignedBuilds", isDirectory: true)
        try fm.createDirectory(at: builds, withIntermediateDirectories: true)
        let safeName = appName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let output = builds.appendingPathComponent("\(safeName)-signed.ipa")
        try? fm.removeItem(at: output)
        try fm.zipItem(at: payload, to: output, shouldKeepParent: true, compressionMethod: .deflate)

        guard fm.fileExists(atPath: output.path) else {
            throw ReyForgeSigningError.validationFailed("signed IPA was not written")
        }
        return output
    }

    nonisolated private static func rewriteMainIdentity(
        appURL: URL,
        oldIdentifier: String,
        newIdentifier: String,
        appName: String
    ) throws {
        let infoURL = appURL.appendingPathComponent("Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL)?.mutableCopy() as? NSMutableDictionary else {
            throw ReyForgeSigningError.invalidArchive
        }
        info["CFBundleIdentifier"] = newIdentifier
        info["CFBundleDisplayName"] = appName
        info["CFBundleName"] = appName
        rewriteIdentifierReferences(in: info, oldIdentifier: oldIdentifier, newIdentifier: newIdentifier)
        guard info.write(to: infoURL, atomically: true) else {
            throw ReyForgeSigningError.validationFailed("could not write main Info.plist")
        }
    }

    nonisolated private static func rewriteNestedBundleIdentifiers(
        inside appURL: URL,
        oldIdentifier: String,
        newIdentifier: String
    ) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: appURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            guard ext == "appex" || ext == "app" else { continue }
            guard url.standardizedFileURL != appURL.standardizedFileURL else { continue }

            let infoURL = url.appendingPathComponent("Info.plist")
            guard let info = NSDictionary(contentsOf: infoURL)?.mutableCopy() as? NSMutableDictionary else { continue }
            if let current = info["CFBundleIdentifier"] as? String {
                info["CFBundleIdentifier"] = replacingIdentifierPrefix(current, old: oldIdentifier, new: newIdentifier)
            }
            rewriteIdentifierReferences(in: info, oldIdentifier: oldIdentifier, newIdentifier: newIdentifier)
            _ = info.write(to: infoURL, atomically: true)
        }
    }

    nonisolated private static func rewriteIdentifierReferences(
        in info: NSMutableDictionary,
        oldIdentifier: String,
        newIdentifier: String
    ) {
        for key in ["WKCompanionAppBundleIdentifier"] {
            if let value = info[key] as? String {
                info[key] = replacingIdentifierPrefix(value, old: oldIdentifier, new: newIdentifier)
            }
        }

        if let extensionDict = (info["NSExtension"] as? NSDictionary)?.mutableCopy() as? NSMutableDictionary {
            if let group = extensionDict["NSExtensionFileProviderDocumentGroup"] as? String {
                extensionDict["NSExtensionFileProviderDocumentGroup"] = replacingIdentifierPrefix(group, old: oldIdentifier, new: newIdentifier)
            }
            if let attributes = (extensionDict["NSExtensionAttributes"] as? NSDictionary)?.mutableCopy() as? NSMutableDictionary {
                if let watchID = attributes["WKAppBundleIdentifier"] as? String {
                    attributes["WKAppBundleIdentifier"] = replacingIdentifierPrefix(watchID, old: oldIdentifier, new: newIdentifier)
                }
                extensionDict["NSExtensionAttributes"] = attributes
            }
            info["NSExtension"] = extensionDict
        }
    }

    nonisolated private static func replacingIdentifierPrefix(_ value: String, old: String, new: String) -> String {
        if value == old { return new }
        if value.hasPrefix(old + ".") {
            return new + value.dropFirst(old.count)
        }
        return value.replacingOccurrences(of: old, with: new)
    }
}

struct ReyForgeSigningPanel: View {
    @EnvironmentObject private var store: StudioStore
    @EnvironmentObject private var github: GitHubBuildManager
    @EnvironmentObject private var signer: BuiltInSigningManager
    @State private var importingBundle = false
    @State private var importingIPA = false

    private var selectedIPA: URL? {
        signer.importedIPAURL ?? github.ipaURL
    }

    private var ipaType: UTType {
        UTType(filenameExtension: "ipa") ?? .data
    }

    var body: some View {
        Form {
            Section("Local signer") {
                LabeledContent("Status", value: signer.status)
                LabeledContent("Profile App ID", value: signer.profileBundleIdentifier)
                LabeledContent("Profile", value: "Your registered iPhone · expires \(signer.profileExpirationText)")

                if !signer.isConfigured {
                    Button {
                        importingBundle = true
                    } label: {
                        Label("Import Signing ZIP", systemImage: "lock.doc")
                    }
                }

                Button {
                    importingIPA = true
                } label: {
                    Label(signer.isImportingIPA ? "Importing IPA…" : "Import IPA to Sign", systemImage: "square.and.arrow.down")
                }
                .disabled(signer.isImportingIPA || signer.isSigning)

                if !signer.diagnostic.isEmpty {
                    Text(signer.diagnostic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = signer.lastError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }

            Section("App identity") {
                TextField("App name", text: $signer.targetAppName)
                    .textInputAutocapitalization(.words)
                TextField("Bundle identifier", text: $signer.targetBundleIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if signer.importedIPAURL == nil, let project = store.selected {
                    Button("Use Project Name & Bundle ID") {
                        signer.setTargetIdentity(name: project.name, bundleIdentifier: project.bundleIdentifier)
                    }
                    Text("Project default: \(project.name) · \(project.bundleIdentifier)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Like Feather, ReyForge rewrites CFBundleIdentifier before signing and updates nested app/extension identifiers that use the original bundle-ID prefix.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Build & sign") {
                if let ipa = selectedIPA {
                    LabeledContent(signer.importedIPAURL == nil ? "Generated IPA" : "Imported IPA", value: ipa.lastPathComponent)
                    Button {
                        let hasWidget = signer.importedIPAURL == nil ? (store.selected?.widget.enabled ?? false) : false
                        Task { await signer.sign(ipaURL: ipa, widgetEnabled: hasWidget) }
                    } label: {
                        Label(signer.isSigning ? "Signing…" : "Sign IPA Locally", systemImage: "signature")
                    }
                    .disabled(signer.isSigning)
                } else {
                    Text("Import an IPA above, or build one in ReyForge first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let signed = signer.signedIPAURL {
                    ShareLink(item: signed) {
                        Label("Export Signed IPA", systemImage: "square.and.arrow.up")
                    }
                    LabeledContent("Signed file", value: signed.lastPathComponent)
                    if let name = signer.signedAppName {
                        LabeledContent("Signed name", value: name)
                    }
                    if let identifier = signer.signedBundleIdentifier {
                        LabeledContent("Signed bundle ID", value: identifier)
                    }
                }
            }

            Section("Provisioning note") {
                Text("ReyForge no longer forces every app to \(signer.profileBundleIdentifier). It signs the identity you enter, matching Feather's behavior. iOS still makes the final decision about whether the selected provisioning profile authorizes that identity and its entitlements.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .task(id: store.selectedID) {
            guard signer.importedIPAURL == nil, let project = store.selected else { return }
            signer.setTargetIdentity(name: project.name, bundleIdentifier: project.bundleIdentifier)
        }
        .fileImporter(isPresented: $importingBundle, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result {
                Task { await signer.importSigningBundle(url) }
            }
        }
        .fileImporter(isPresented: $importingIPA, allowedContentTypes: [ipaType]) { result in
            if case .success(let url) = result {
                Task { await signer.importIPA(url) }
            }
        }
    }
}
