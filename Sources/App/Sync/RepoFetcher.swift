import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Vapor

struct RepoFetchOutcome {
    let extractPath: URL
    /// Resolved full Git SHA when derivable from the archive layout or API.
    let resolvedCommitSha: String?
}

struct RepoFetcher {
    let app: Application

    func fetch(owner: String, repo: String, ref: String, token: String? = nil) async throws -> RepoFetchOutcome {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/tarball/\(ref)"
        guard let url = URL(string: urlString) else {
            throw RepoFetcherError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let authToken = token ?? Environment.get("GITHUB_TOKEN")
        if let authToken = authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let session: URLSession
        if let authToken = authToken {
            let delegate = GitHubTarballRedirectDelegate(bearerToken: authToken)
            session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        } else {
            session = URLSession.shared
        }
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw RepoFetcherError.fetchFailed(status: code)
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tarballPath = tempDir.appendingPathComponent("repo.tar.gz")
        try data.write(to: tarballPath)

        let extractPath = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractPath, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", tarballPath.path, "-C", extractPath.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: tempDir)
            throw RepoFetcherError.extractFailed
        }

        let repoRoot = try resolveRepositoryRoot(extractPath: extractPath)
        let fromArchive = Self.parseCommitShaFromArchiveDirectoryName(repoRoot)
        return RepoFetchOutcome(extractPath: extractPath, resolvedCommitSha: fromArchive)
    }

    /// `GET /repos/{owner}/{repo}/commits/{ref}` — used when the archive folder name does not include a full SHA.
    func resolveCommitShaViaApi(owner: String, repo: String, ref: String, token: String?) async throws -> String? {
        let encodedRef =
            ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/commits/\(encodedRef)"
        let uri = URI(string: urlString)

        let response = try await app.client.get(uri) { req in
            if let token {
                req.headers.bearerAuthorization = BearerAuthorization(token: token)
            }
            req.headers.add(name: "Accept", value: "application/vnd.github+json")
            req.headers.add(name: "X-GitHub-Api-Version", value: "2022-11-28")
            req.headers.add(name: "User-Agent", value: "MyContextProtocol/1")
        }
        guard response.status == .ok, let body = response.body else {
            return nil
        }
        struct CommitDto: Decodable { let sha: String }
        let data = Data(buffer: body)
        return try? JSONDecoder().decode(CommitDto.self, from: data).sha
    }

    /// GitHub tarball extracts to a single directory named `{owner}-{repo}-{fullSha}`.
    static func parseCommitShaFromArchiveDirectoryName(_ repoRoot: URL) -> String? {
        let name = repoRoot.lastPathComponent
        guard let regex = try? NSRegularExpression(pattern: "[a-f0-9]{40}$", options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(name.startIndex..., in: name)
        guard let m = regex.firstMatch(in: name, options: [], range: range),
              let swiftRange = Range(m.range, in: name) else { return nil }
        return String(name[swiftRange])
    }

    /// Picks the directory GitHub’s tarball uses as the **clone root** so paths don’t start with `{owner}-{repo}-{sha}/`.
    ///
    /// - **Normal case:** `extractPath` has exactly one child directory (the archive root). We descend into it; inside it the
    ///   repo may have **many** top-level folders (`Workflow/`, `CodingStyle/`, etc.). That is fine — `findSkillFiles` is **recursive**
    ///   and collects every `**/SKILL.md`. Relative paths look like `Workflow/some-skill/SKILL.md`.
    /// - **Edge case:** several immediate children under `extractPath` (unusual). We keep `extractPath` as the scan root and still
    ///   recurse the whole tree; nothing requires a flat repo layout beyond “each skill is some `skill-name/SKILL.md` anywhere under root.”
    func resolveRepositoryRoot(extractPath: URL) throws -> URL {
        let urls = try FileManager.default.contentsOfDirectory(
            at: extractPath,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let directories = urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        if directories.count == 1 {
            return directories[0]
        }
        return extractPath
    }

    func findSkillFiles(in directory: URL) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true
            else { continue }

            if fileURL.lastPathComponent == "SKILL.md" {
                results.append(fileURL)
            }
        }
        return results
    }
}

enum RepoFetcherError: Error {
    case invalidURL
    case fetchFailed(status: Int)
    case extractFailed
}
