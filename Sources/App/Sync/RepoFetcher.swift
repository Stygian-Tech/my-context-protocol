import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Vapor

struct RepoFetcher {
    let app: Application

    func fetch(owner: String, repo: String, ref: String, token: String? = nil) async throws -> URL {
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

        return extractPath
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
