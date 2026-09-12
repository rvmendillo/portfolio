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

@MainActor
final class BuiltInSigningManager: ObservableObject {
    @Published var status = "Checking signing assets…"
    @Published var isSigning = false
    @Published var isImporting = false
    @Published var isImportingIPA = false
    @Published private(set) var signedArtifact: SignedIPA?
    @Published private(set) var importedIPAURL: URL?
    @Published var signingPassword = ""
    @Published private(set) var profileMetadata: ProvisioningMetadata?
    var signedIPAURL: URL? { signedArtifact?.url }
    var signedBundleIdentifier: String? { signedArtifact?.identity.bundleIdentifier }
    var signedAppName: String? { signedArtifact?.identity.name }
    var isBusy: Bool { isSigning || isImporting || isImportingIPA }
    @Published var lastError: String?
    @Published var diagnostic = ""
    @Published var targetAppName = "My App"
    @Published var targetBundleIdentifier = "com.rvmendillo.myapp"
    var profileBundleIdentifier: String { profileMetadata?.appIDPattern ?? "Not configured" }
    var profileExpirationText: String {
        profileMetadata?.expiration.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
    }
    var provisionedBundleIdentifier: String { signedBundleIdentifier ?? "" }
    private let artifactKey = "reyforge.signed-artifact.v1"

    private let builtInPassword = "1"
    private let fileManager = FileManager.default

    init() {
        installBundledAssetsIfNeeded()
        reloadProfileMetadata()
        if let data = UserDefaults.standard.data(forKey: artifactKey),
           let saved = try? JSONDecoder().decode(SignedIPA.self, from: data) {
            // iOS may change the sandbox path when updating an app.
            let file = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SignedBuilds")
                .appendingPathComponent(saved.url.lastPathComponent)
            if fileManager.fileExists(atPath: file.path) {
                signedArtifact = SignedIPA(url: file, identity: saved.identity)
            }
        }
        status = signedArtifact != nil ? "Signed IPA ready" : (isConfigured ? "Local signer ready" : "Import signing bundle")
    }

    var isConfigured: Bool {
        fileManager.fileExists(atPath: p12URL.path) &&
        fileManager.fileExists(atPath: provisionURL.path)
    }

    func setTargetIdentity(name: String, bundleIdentifier: String) {
        targetAppName = name
        targetBundleIdentifier = bundleIdentifier
    }

    private func reloadProfileMetadata() {
        profileMetadata = (try? Data(contentsOf: provisionURL)).flatMap { try? ProvisioningMetadata(data: $0) }
    }

    private func invalidateSignedArtifact() {
        signedArtifact = nil
        UserDefaults.standard.removeObject(forKey: artifactKey)
    }

    func useGeneratedIPA() {
        guard !isBusy else { return }
        importedIPAURL = nil
        invalidateSignedArtifact()
        lastError = nil
        diagnostic = ""
        status = "Generated IPA selected"
    }

    func importSigningBundle(_ url: URL) async {
        guard !isBusy else { return }
        isImporting = true
        defer { isImporting = false }
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

                _ = try ProvisioningMetadata(data: Data(contentsOf: provision))
                let staging = destination.deletingLastPathComponent()
                    .appendingPathComponent("SigningVault-\(UUID().uuidString)")
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: staging) }
                try fm.copyItem(at: p12, to: staging.appendingPathComponent("distribution.p12"))
                try fm.copyItem(at: provision, to: staging.appendingPathComponent("distribution.mobileprovision"))
                if fm.fileExists(atPath: destination.path) {
                    _ = try fm.replaceItemAt(destination, withItemAt: staging)
                } else {
                    try fm.moveItem(at: staging, to: destination)
                }
            }.value

            try SigningPasswordStore.save(signingPassword)
            signingPassword = ""
            reloadProfileMetadata()
            invalidateSignedArtifact()
            diagnostic = "P12 and provisioning profile imported"
            status = "Local signer ready"
            objectWillChange.send()
        } catch {
            lastError = error.localizedDescription
            diagnostic = "Signing bundle import failed"
            status = "Signing import failed"
        }

        isImporting = false
    }

    func importIPA(_ url: URL) async {
        guard !isBusy else { return }
        isImportingIPA = true
        defer { isImportingIPA = false }
        invalidateSignedArtifact()
        lastError = nil
        status = "Importing IPA…"
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let result = try await Task.detached(priority: .userInitiated) { () -> (URL, IPAIdentity) in
                let fm = FileManager.default
                let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("SigningInputs", isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let identity = try Self.inspectIPA(url)
                let target = dir.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
                try fm.copyItem(at: url, to: target)
                return (target, identity)
            }.value

            let oldInput = importedIPAURL
            importedIPAURL = result.0
            targetAppName = result.1.name
            targetBundleIdentifier = result.1.bundleIdentifier
            if let oldInput, oldInput != result.0 { try? fileManager.removeItem(at: oldInput) }
            diagnostic = "Imported \(result.0.lastPathComponent)"
            status = "IPA ready to sign"
        } catch {
            lastError = error.localizedDescription
            status = "IPA import failed"
        }
        isImportingIPA = false
    }

    func sign(ipaURL: URL, widgetEnabled: Bool) async {
        guard !isBusy else { return }
        invalidateSignedArtifact()
        guard isConfigured else {
            lastError = ReyForgeSigningError.signingAssetsMissing.localizedDescription
            return
        }

        let identifier = targetBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppIdentity.isValid(identifier) else {
            lastError = ReyForgeSigningError.invalidBundleIdentifier.localizedDescription
            return
        }
        do {
            let protected = [AppIdentity.reyForge, AppIdentity.legacyReyForge, Bundle.main.bundleIdentifier ?? ""]
            guard !protected.contains(identifier) else { throw IdentityError.selfReplacement }
            guard let profileMetadata else { throw IdentityError.invalidProfile }
            try profileMetadata.validate(identifier: identifier)
        } catch {
            lastError = error.localizedDescription
            status = "Signing identity needs attention"
            return
        }
        let requestedName = targetAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        let appName = requestedName.isEmpty ? "Signed App" : requestedName

        isSigning = true
        defer { isSigning = false }
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
            signedArtifact = output
            if let data = try? JSONEncoder().encode(output) {
                UserDefaults.standard.set(data, forKey: artifactKey)
            }
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
        invalidateSignedArtifact()
        profileMetadata = nil
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
        let apps = items.filter { $0.pathExtension.lowercased() == "app" }
        guard apps.count == 1, let appURL = apps.first,
              let data = try? Data(contentsOf: appURL.appendingPathComponent("Info.plist")),
              let info = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw IdentityError.invalidApp
        }
        return try IPAIdentity(info: info, fallbackName: appURL.deletingPathExtension().lastPathComponent)
    }

    nonisolated private static func signSynchronously(
        ipaURL: URL,
        p12URL: URL,
        provisionURL: URL,
        password: String,
        bundleIdentifier: String,
        appName: String
    ) throws -> SignedIPA {
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
        let apps = payloadItems.filter { $0.pathExtension.lowercased() == "app" }
        guard apps.count == 1, let appURL = apps.first else { throw IdentityError.invalidApp }
        let profile = try ProvisioningMetadata(data: Data(contentsOf: provisionURL))
        try profile.validate(identifier: bundleIdentifier)

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

        // Nested targets need their own permitted identities too.
        if let targets = fm.enumerator(at: appURL, includingPropertiesForKeys: nil) {
            for case let target as URL in targets where ["app", "appex"].contains(target.pathExtension) {
                if let info = NSDictionary(contentsOf: target.appendingPathComponent("Info.plist")),
                   let identifier = info["CFBundleIdentifier"] as? String {
                    try profile.validate(identifier: identifier)
                }
            }
        }

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
        let output = builds.appendingPathComponent("\(safeName)-\(UUID().uuidString.prefix(8))-signed.ipa")
        try fm.zipItem(at: payload, to: output, shouldKeepParent: true, compressionMethod: .deflate)

        guard fm.fileExists(atPath: output.path) else {
            throw ReyForgeSigningError.validationFailed("signed IPA was not written")
        }
        let identity = try inspectIPA(output)
        guard identity.bundleIdentifier == bundleIdentifier, identity.name == appName else {
            try? fm.removeItem(at: output)
            throw ReyForgeSigningError.validationFailed("archive identity changed during packaging")
        }
        return SignedIPA(url: output, identity: identity)
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
            guard info.write(to: infoURL, atomically: true) else {
                throw ReyForgeSigningError.validationFailed("could not update a nested app identity")
            }
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
        return value
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
                LabeledContent("Expires", value: signer.profileExpirationText)

                SecureField("Signing ZIP password (empty if none)", text: $signer.signingPassword)
                    .textContentType(.password)
                Group {
                    Button {
                        importingBundle = true
                    } label: {
                        Label(signer.isConfigured ? "Replace Signing ZIP" : "Import Signing ZIP", systemImage: "lock.doc")
                    }
                }

                Button {
                    importingIPA = true
                } label: {
                    Label(signer.isImportingIPA ? "Importing IPA…" : "Import IPA to Sign", systemImage: "square.and.arrow.down")
                }
                .disabled(signer.isImportingIPA || signer.isSigning)

                if signer.importedIPAURL != nil, github.ipaURL != nil {
                    Button("Use Generated IPA") {
                        signer.useGeneratedIPA()
                        if let project = store.selected {
                            signer.setTargetIdentity(name: project.name, bundleIdentifier: project.bundleIdentifier)
                        }
                    }
                }

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
                Text("Each app needs its own bundle ID and a profile that permits it. ReyForge checks the requested identity before signing, so apps stay separate when switching between them.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .disabled(signer.isBusy)
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
