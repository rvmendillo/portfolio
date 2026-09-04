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
    case noSigningPair
    case widgetNeedsProfile
    case signFailed(String)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .signingAssetsMissing:
            return "Signing assets are not configured."
        case .invalidArchive:
            return "The IPA or signing bundle could not be opened."
        case .noSigningPair:
            return "No matching .p12 and .mobileprovision pair was found."
        case .widgetNeedsProfile:
            return "This profile signs the main app only. WidgetKit extensions need a separate provisioning profile. Disable Widget export for this certificate."
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
    @Published var signedIPAURL: URL?
    @Published var importedIPAURL: URL?
    @Published var lastError: String?
    @Published var diagnostic = ""

    let provisionedBundleIdentifier = "app.seaweed4660.tiger8048"
    let profileExpirationText = "March 2027"

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
            let destination = try await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("SigningInputs", isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let cleanName = url.lastPathComponent.lowercased().hasSuffix(".ipa") ? url.lastPathComponent : "Imported.ipa"
                let target = dir.appendingPathComponent(cleanName)
                try? fm.removeItem(at: target)
                try fm.copyItem(at: url, to: target)
                return target
            }.value
            importedIPAURL = destination
            diagnostic = "Imported \(destination.lastPathComponent)"
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
        guard !widgetEnabled else {
            lastError = ReyForgeSigningError.widgetNeedsProfile.localizedDescription
            return
        }

        isSigning = true
        signedIPAURL = nil
        lastError = nil
        diagnostic = "Preparing \(ipaURL.lastPathComponent)"
        status = "Signing IPA on device…"

        do {
            let p12 = p12URL
            let profile = provisionURL
            let password = SigningPasswordStore.load() ?? builtInPassword
            let identifier = provisionedBundleIdentifier
            let output = try await Task.detached(priority: .userInitiated) {
                try Self.signSynchronously(
                    ipaURL: ipaURL,
                    p12URL: p12,
                    provisionURL: profile,
                    password: password,
                    bundleIdentifier: identifier
                )
            }.value
            signedIPAURL = output
            diagnostic = "Signature, App ID, and embedded profile verified"
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

    nonisolated private static func signSynchronously(
        ipaURL: URL,
        p12URL: URL,
        provisionURL: URL,
        password: String,
        bundleIdentifier: String
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

        let plugins = appURL.appendingPathComponent("PlugIns", isDirectory: true)
        if let pluginItems = try? fm.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil),
           pluginItems.contains(where: { $0.pathExtension.lowercased() == "appex" }) {
            throw ReyForgeSigningError.widgetNeedsProfile
        }

        // Put the profile in place before signing so it is part of the final signed bundle.
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
            customName: "",
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

        let infoURL = appURL.appendingPathComponent("Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL),
              let actualIdentifier = info["CFBundleIdentifier"] as? String,
              actualIdentifier == bundleIdentifier else {
            throw ReyForgeSigningError.validationFailed("bundle identifier was not changed to the provisioning profile App ID")
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
        let base = ipaURL.deletingPathExtension().lastPathComponent
        let output = builds.appendingPathComponent("\(base)-signed.ipa")
        try? fm.removeItem(at: output)
        try fm.zipItem(at: payload, to: output, shouldKeepParent: true, compressionMethod: .deflate)

        guard fm.fileExists(atPath: output.path) else {
            throw ReyForgeSigningError.validationFailed("signed IPA was not written")
        }
        return output
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
                LabeledContent("Allowed App ID", value: signer.provisionedBundleIdentifier)
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
                }
            }

            Section("Current profile limitation") {
                Text("This provisioning profile has one explicit App ID. Every IPA signed with it becomes \(signer.provisionedBundleIdentifier), so installing another signed app can replace ReyForge. A wildcard profile or another App ID/profile is required for separate installed apps.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if store.selected?.widget.enabled == true && signer.importedIPAURL == nil {
                Section("Widget signing") {
                    Label("A WidgetKit extension needs its own provisioning profile.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Your current explicit profile only covers the main app App ID, so ReyForge blocks invalid widget signing instead of producing an IPA that iOS will reject.")
                        .font(.caption)
                }
            }
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
