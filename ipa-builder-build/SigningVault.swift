import Foundation
import SwiftUI
import Security
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
    case signFailed

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
        case .signFailed:
            return "Local Zsign signing failed."
        }
    }
}

@MainActor
final class BuiltInSigningManager: ObservableObject {
    @Published var status = "Checking signing assets…"
    @Published var isSigning = false
    @Published var isImporting = false
    @Published var signedIPAURL: URL?
    @Published var lastError: String?

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
        status = "Importing signing bundle…"

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let destination = vaultDirectory
            let password = builtInPassword
            try await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                let temp = fm.temporaryDirectory.appendingPathComponent("ReyForgeSigningImport-\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: temp, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: temp) }

                if url.pathExtension.lowercased() == "zip" {
                    try fm.unzipItem(at: url, to: temp)
                } else {
                    throw ReyForgeSigningError.invalidArchive
                }

                let files = try fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                let p12 = files.first { $0.pathExtension.lowercased() == "p12" && $0.lastPathComponent.lowercased().contains("distribution") }
                    ?? files.first { $0.pathExtension.lowercased() == "p12" }
                let provision = files.first { $0.pathExtension.lowercased() == "mobileprovision" && $0.lastPathComponent.lowercased().contains("distribution") }
                    ?? files.first { $0.pathExtension.lowercased() == "mobileprovision" }

                guard let p12, let provision else { throw ReyForgeSigningError.noSigningPair }

                try? fm.removeItem(at: destination)
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                try fm.copyItem(at: p12, to: destination.appendingPathComponent("distribution.p12"))
                try fm.copyItem(at: provision, to: destination.appendingPathComponent("distribution.mobileprovision"))

                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var mutable = destination
                try? mutable.setResourceValues(values)
                _ = password
            }.value

            try? SigningPasswordStore.save(builtInPassword)
            status = "Built-in signer ready"
            objectWillChange.send()
        } catch {
            lastError = error.localizedDescription
            status = "Signing import failed"
        }

        isImporting = false
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
            status = "Signed IPA ready"
        } catch {
            lastError = error.localizedDescription
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
        let root = fm.temporaryDirectory.appendingPathComponent("ReyForgeSign-\(UUID().uuidString)", isDirectory: true)
        let extract = root.appendingPathComponent("Extracted", isDirectory: true)
        try fm.createDirectory(at: extract, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try fm.unzipItem(at: ipaURL, to: extract)
        let payload = extract.appendingPathComponent("Payload", isDirectory: true)
        let payloadItems = try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        guard let appURL = payloadItems.first(where: { $0.pathExtension == "app" }) else {
            throw ReyForgeSigningError.invalidArchive
        }

        let plugins = appURL.appendingPathComponent("PlugIns", isDirectory: true)
        if let pluginItems = try? fm.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil),
           pluginItems.contains(where: { $0.pathExtension == "appex" }) {
            throw ReyForgeSigningError.widgetNeedsProfile
        }

        let signed = Zsign.sign(
            appPath: appURL.path,
            provisionPath: provisionURL.path,
            p12Path: p12URL.path,
            p12Password: password,
            entitlementsPath: "",
            customIdentifier: bundleIdentifier,
            customName: "",
            customVersion: "",
            adhoc: false,
            removeProvision: false
        )
        guard signed else { throw ReyForgeSigningError.signFailed }

        let builds = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SignedBuilds", isDirectory: true)
        try fm.createDirectory(at: builds, withIntermediateDirectories: true)
        let base = ipaURL.deletingPathExtension().lastPathComponent
        let output = builds.appendingPathComponent("\(base)-signed.ipa")
        try? fm.removeItem(at: output)
        try fm.zipItem(at: payload, to: output, shouldKeepParent: true, compressionMethod: .deflate)
        return output
    }
}

struct ReyForgeSigningPanel: View {
    @EnvironmentObject private var store: StudioStore
    @EnvironmentObject private var github: GitHubBuildManager
    @EnvironmentObject private var signer: BuiltInSigningManager
    @State private var importing = false

    var body: some View {
        Form {
            Section("Local signer") {
                LabeledContent("Status", value: signer.status)
                LabeledContent("Allowed App ID", value: signer.provisionedBundleIdentifier)
                LabeledContent("Profile", value: "Your registered iPhone · expires \(signer.profileExpirationText)")

                if !signer.isConfigured {
                    Button {
                        importing = true
                    } label: {
                        Label("Import Signing ZIP", systemImage: "lock.doc")
                    }
                }

                if let error = signer.lastError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }

            Section("Build & sign") {
                if let ipa = github.ipaURL {
                    LabeledContent("Unsigned", value: ipa.lastPathComponent)
                    Button {
                        Task { await signer.sign(ipaURL: ipa, widgetEnabled: store.selected?.widget.enabled ?? false) }
                    } label: {
                        Label(signer.isSigning ? "Signing…" : "Sign IPA Locally", systemImage: "signature")
                    }
                    .disabled(signer.isSigning)
                } else {
                    Text("Build an IPA first. ReyForge will sign it locally after GitHub returns the unsigned build.")
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

            if store.selected?.widget.enabled == true {
                Section("Widget signing") {
                    Label("A WidgetKit extension needs its own provisioning profile.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Your current explicit profile only covers the main app App ID, so ReyForge blocks invalid widget signing instead of producing an IPA that iOS will reject.")
                        .font(.caption)
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result {
                Task { await signer.importSigningBundle(url) }
            }
        }
    }
}
