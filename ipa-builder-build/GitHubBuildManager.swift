import Foundation
import Security
import ZIPFoundation

enum KeychainStore {
    private static let service = "com.rvmendillo.ipabuilder.github"
    private static let account = "github-token"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

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

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct GitHubAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct ContentUploadResponse: Decodable {
    struct ContentInfo: Decodable { let sha: String }
    struct CommitInfo: Decodable { let sha: String }
    let content: ContentInfo?
    let commit: CommitInfo?
}

private struct WorkflowRunEnvelope: Decodable {
    let workflow_runs: [WorkflowRun]
}

private struct WorkflowRun: Decodable {
    let id: Int64
    let status: String
    let conclusion: String?
    let display_title: String
    let html_url: String?
    let head_sha: String
}

private struct ArtifactEnvelope: Decodable {
    let artifacts: [WorkflowArtifact]
}

private struct WorkflowArtifact: Decodable {
    let id: Int64
    let name: String
    let expired: Bool
}

@MainActor
final class GitHubBuildManager: ObservableObject {
    @Published var token: String
    @Published var owner: String
    @Published var repo: String
    @Published var status = "Ready"
    @Published var isBuilding = false
    @Published var ipaURL: URL?
    @Published var lastRunURL: URL?
    @Published var lastError: String?

    private let workflowFile = "ipa-builder-service.yml"
    private let jobsBranch = "ipa-builder-jobs"

    init() {
        token = KeychainStore.load()
        owner = UserDefaults.standard.string(forKey: "github.owner") ?? "rvmendillo"
        repo = UserDefaults.standard.string(forKey: "github.repo") ?? "portfolio"
    }

    var hasCredential: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveCredential() {
        do {
            let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else {
                throw GitHubAPIError(message: "Enter a GitHub token first.")
            }
            try KeychainStore.save(clean)
            token = clean
            UserDefaults.standard.set(owner, forKey: "github.owner")
            UserDefaults.standard.set(repo, forKey: "github.repo")
            status = "GitHub access saved in Keychain"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        KeychainStore.delete()
        token = ""
        ipaURL = nil
        lastRunURL = nil
        status = "Disconnected"
    }

    func build(project: BuilderProject) async {
        guard hasCredential else {
            lastError = "Save a GitHub access token first."
            return
        }

        isBuilding = true
        ipaURL = nil
        lastRunURL = nil
        lastError = nil

        let jobID = UUID().uuidString.lowercased()
        let jobPath = "ipa-builder-jobs/\(jobID)/project.json"
        var uploadedContentSHA: String?

        do {
            status = "Uploading project to GitHub…"
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let projectData = try encoder.encode(project)
            let upload = try await uploadProject(projectData, path: jobPath, jobID: jobID)
            uploadedContentSHA = upload.contentSHA

            status = "macOS build queued…"
            let run = try await findRun(commitSHA: upload.commitSHA)
            if let urlString = run.html_url {
                lastRunURL = URL(string: urlString)
            }

            let completed = try await waitForCompletion(runID: run.id)
            guard completed.conclusion == "success" else {
                throw GitHubAPIError(message: "GitHub build finished with: \(completed.conclusion ?? "unknown")")
            }

            status = "Downloading IPA artifact…"
            let artifact = try await findArtifact(runID: run.id, jobID: jobID)
            let zipData = try await downloadArtifact(id: artifact.id)

            status = "Extracting IPA…"
            ipaURL = try extractIPA(zipData: zipData, projectName: project.name, jobID: jobID)
            status = "IPA ready"
        } catch {
            lastError = error.localizedDescription
            status = "Build failed"
        }

        if let uploadedContentSHA {
            try? await deleteProject(path: jobPath, sha: uploadedContentSHA, jobID: jobID)
        }

        isBuilding = false
    }

    private func apiURL(path: String, query: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = path
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw GitHubAPIError(message: "Invalid GitHub API URL.")
        }
        return url
    }

    private func request(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        jsonBody: Any? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: try apiURL(path: path, query: query))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubAPIError(message: "GitHub returned an invalid response.")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubAPIError(message: "GitHub API \(http.statusCode): \(body.isEmpty ? "request failed" : body)")
        }
        return (data, http)
    }

    private func uploadProject(
        _ data: Data,
        path: String,
        jobID: String
    ) async throws -> (contentSHA: String, commitSHA: String) {
        let body: [String: Any] = [
            "message": "IPA Builder job \(jobID)",
            "content": data.base64EncodedString(),
            "branch": jobsBranch
        ]

        let (responseData, _) = try await request(
            path: "/repos/\(owner)/\(repo)/contents/\(path)",
            method: "PUT",
            jsonBody: body
        )

        let response = try JSONDecoder().decode(ContentUploadResponse.self, from: responseData)
        guard let contentSHA = response.content?.sha,
              let commitSHA = response.commit?.sha else {
            throw GitHubAPIError(message: "Project upload did not return GitHub commit metadata.")
        }
        return (contentSHA, commitSHA)
    }

    private func findRun(commitSHA: String) async throws -> WorkflowRun {
        for _ in 0..<80 {
            let (data, _) = try await request(
                path: "/repos/\(owner)/\(repo)/actions/workflows/\(workflowFile)/runs",
                query: [
                    URLQueryItem(name: "event", value: "push"),
                    URLQueryItem(name: "branch", value: jobsBranch),
                    URLQueryItem(name: "per_page", value: "30")
                ]
            )
            let envelope = try JSONDecoder().decode(WorkflowRunEnvelope.self, from: data)
            if let run = envelope.workflow_runs.first(where: { $0.head_sha == commitSHA }) {
                return run
            }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
        throw GitHubAPIError(message: "The macOS build did not appear in GitHub Actions.")
    }

    private func waitForCompletion(runID: Int64) async throws -> WorkflowRun {
        for _ in 0..<160 {
            let (data, _) = try await request(path: "/repos/\(owner)/\(repo)/actions/runs/\(runID)")
            let run = try JSONDecoder().decode(WorkflowRun.self, from: data)
            status = run.status == "queued" ? "macOS runner queued…" : "macOS runner: \(run.status)…"
            if run.status == "completed" {
                return run
            }
            try await Task.sleep(nanoseconds: 4_000_000_000)
        }
        throw GitHubAPIError(message: "Build monitoring timed out.")
    }

    private func findArtifact(runID: Int64, jobID: String) async throws -> WorkflowArtifact {
        let (data, _) = try await request(path: "/repos/\(owner)/\(repo)/actions/runs/\(runID)/artifacts")
        let envelope = try JSONDecoder().decode(ArtifactEnvelope.self, from: data)
        guard let artifact = envelope.artifacts.first(where: { $0.name == "ipa-\(jobID)" && !$0.expired }) else {
            throw GitHubAPIError(message: "The completed run did not expose the expected IPA artifact.")
        }
        return artifact
    }

    private func downloadArtifact(id: Int64) async throws -> Data {
        let (data, _) = try await request(path: "/repos/\(owner)/\(repo)/actions/artifacts/\(id)/zip")
        return data
    }

    private func deleteProject(path: String, sha: String, jobID: String) async throws {
        let body: [String: Any] = [
            "message": "[skip ci] Clean IPA Builder job \(jobID)",
            "sha": sha,
            "branch": jobsBranch
        ]
        _ = try await request(
            path: "/repos/\(owner)/\(repo)/contents/\(path)",
            method: "DELETE",
            jsonBody: body
        )
    }

    private func extractIPA(zipData: Data, projectName: String, jobID: String) throws -> URL {
        let fileManager = FileManager.default
        let tempZIP = fileManager.temporaryDirectory.appendingPathComponent("artifact-\(jobID).zip")
        try zipData.write(to: tempZIP, options: .atomic)

        let archive = try Archive(url: tempZIP, accessMode: .read)
        guard let entry = archive.first(where: { $0.type == .file && $0.path.lowercased().hasSuffix(".ipa") }) else {
            throw GitHubAPIError(message: "Downloaded artifact did not contain an IPA.")
        }

        let buildsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Builds", isDirectory: true)
        try fileManager.createDirectory(at: buildsDirectory, withIntermediateDirectories: true)

        let safeName = projectName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let destination = buildsDirectory.appendingPathComponent("\(safeName)-\(jobID.prefix(8)).ipa")

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try archive.extract(entry, to: destination)
        try? fileManager.removeItem(at: tempZIP)
        return destination
    }
}
