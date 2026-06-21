import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Vapor

struct RepoFetchOutcome {
    let extractPath: URL
    let tempRoot: URL
    /// Resolved full Git SHA when derivable from the archive layout or API.
    let resolvedCommitSha: String?
}

struct RepoFetcher {
    let app: Application

    func fetch(owner: String, repo: String, ref: String, token: String? = nil) async throws -> RepoFetchOutcome {
        guard Self.isValidGitHubOwnerOrRepo(owner), Self.isValidGitHubOwnerOrRepo(repo), Self.isValidGitHubRef(ref) else {
            throw RepoFetcherError.invalidURL
        }
        let urlString = "https://api.github.com/repos/\(Self.pathSegmentEscape(owner))/\(Self.pathSegmentEscape(repo))/tarball/\(Self.pathSegmentEscape(ref))"
        guard let url = URL(string: urlString) else {
            throw RepoFetcherError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.fetchTimeoutSeconds()
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
        let maxBytes = Self.maxTarballBytes()
        guard data.count <= maxBytes else {
            throw RepoFetcherError.tarballTooLarge(maxBytes: maxBytes)
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

        do {
            try await Self.runTar(process)
            try Self.validateExtractedArchive(root: extractPath)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }

        let repoRoot = try resolveRepositoryRoot(extractPath: extractPath)
        let fromArchive = Self.parseCommitShaFromArchiveDirectoryName(repoRoot)
        return RepoFetchOutcome(extractPath: extractPath, tempRoot: tempDir, resolvedCommitSha: fromArchive)
    }

    /// `GET /repos/{owner}/{repo}/commits/{ref}` — used when the archive folder name does not include a full SHA.
    func resolveCommitShaViaApi(owner: String, repo: String, ref: String, token: String?) async throws -> String? {
        guard Self.isValidGitHubOwnerOrRepo(owner), Self.isValidGitHubOwnerOrRepo(repo), Self.isValidGitHubRef(ref) else {
            throw RepoFetcherError.invalidURL
        }
        let urlString = "https://api.github.com/repos/\(Self.pathSegmentEscape(owner))/\(Self.pathSegmentEscape(repo))/commits/\(Self.pathSegmentEscape(ref))"
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

    /// Compiled once; reused across all sync calls.
    private static let _shaRegex = try? NSRegularExpression(pattern: "[a-f0-9]{40}$", options: .caseInsensitive)

    /// GitHub tarball extracts to a single directory named `{owner}-{repo}-{fullSha}`.
    static func parseCommitShaFromArchiveDirectoryName(_ repoRoot: URL) -> String? {
        let name = repoRoot.lastPathComponent
        guard let regex = _shaRegex else { return nil }
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
        let root = directory.standardizedFileURL
        let maxSkills = Environment.get("REPO_MAX_SKILL_FILES").flatMap(Int.init) ?? 5000
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        for case let fileURL as URL in enumerator {
            if results.count >= maxSkills {
                break
            }
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  resourceValues.isRegularFile == true,
                  resourceValues.isSymbolicLink != true
            else { continue }

            if fileURL.lastPathComponent == "SKILL.md" {
                let std = fileURL.standardizedFileURL
                let resolved = fileURL.resolvingSymlinksInPath().standardizedFileURL
                let rp = root.path
                let fp = std.path
                guard fp == rp || fp.hasPrefix(rp + "/") else {
                    continue
                }
                let resolvedPath = resolved.path
                guard resolvedPath == rp || resolvedPath.hasPrefix(rp + "/") else {
                    continue
                }
                results.append(fileURL)
            }
        }
        return results
    }

    static func validateExtractedArchive(root: URL) throws {
        let root = root.standardizedFileURL
        let rootPath = root.path
        let maxEntries = Self.maxExtractedEntries()
        let maxBytes = Self.maxExtractedBytes()
        var entries = 0
        var bytes = 0
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            entries += 1
            guard entries <= maxEntries else {
                throw RepoFetcherError.extractedArchiveTooManyEntries(maxEntries: maxEntries)
            }

            let standardized = url.standardizedFileURL.path
            guard standardized == rootPath || standardized.hasPrefix(rootPath + "/") else {
                throw RepoFetcherError.extractEscaped
            }

            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard resolved == rootPath || resolved.hasPrefix(rootPath + "/") else {
                    throw RepoFetcherError.extractEscaped
                }
            }
            if values.isRegularFile == true {
                bytes += values.fileSize ?? 0
                guard bytes <= maxBytes else {
                    throw RepoFetcherError.extractedArchiveTooLarge(maxBytes: maxBytes)
                }
            }
        }
    }

    private static func runTar(_ process: Process) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    process.terminationHandler = { p in
                        if p.terminationStatus == 0 {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: RepoFetcherError.extractFailed)
                        }
                    }
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(Self.extractTimeoutSeconds() * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
                throw RepoFetcherError.extractTimedOut
            }

            do {
                _ = try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                if process.isRunning {
                    process.terminate()
                }
                throw error
            }
        }
    }

    /// Default 150 MiB cap on downloaded tarball size (ZIP-bomb / memory abuse mitigation).
    private static func maxTarballBytes() -> Int {
        let mb = Environment.get("REPO_TARBALL_MAX_MB").flatMap(Int.init) ?? 150
        return max(10, mb) * 1024 * 1024
    }

    /// Default 500 MiB cap on expanded archive contents.
    private static func maxExtractedBytes() -> Int {
        let mb = Environment.get("REPO_EXTRACT_MAX_MB").flatMap(Int.init) ?? 500
        return max(10, mb) * 1024 * 1024
    }

    private static func maxExtractedEntries() -> Int {
        max(100, Environment.get("REPO_EXTRACT_MAX_ENTRIES").flatMap(Int.init) ?? 20_000)
    }

    private static func fetchTimeoutSeconds() -> TimeInterval {
        max(5, Environment.get("REPO_FETCH_TIMEOUT_SECONDS").flatMap(TimeInterval.init) ?? 60)
    }

    private static func extractTimeoutSeconds() -> TimeInterval {
        max(5, Environment.get("REPO_EXTRACT_TIMEOUT_SECONDS").flatMap(TimeInterval.init) ?? 30)
    }

    static func isValidGitHubOwnerOrRepo(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 100 else { return false }
        return value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    static func isValidGitHubRef(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 255 else { return false }
        if value.hasPrefix("/") || value.hasSuffix("/") || value.contains("..") || value.contains("\\") {
            return false
        }
        if value.contains("\0") || value.contains("\r") || value.contains("\n") {
            return false
        }
        return value.range(of: #"^[A-Za-z0-9._/\-]+$"#, options: .regularExpression) != nil
    }

    static func pathSegmentEscape(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }
}

enum RepoFetcherError: Error {
    case invalidURL
    case fetchFailed(status: Int)
    case extractFailed
    case extractTimedOut
    case extractEscaped
    case tarballTooLarge(maxBytes: Int)
    case extractedArchiveTooLarge(maxBytes: Int)
    case extractedArchiveTooManyEntries(maxEntries: Int)
}
