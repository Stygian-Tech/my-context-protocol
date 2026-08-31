import Fluent
import Vapor
import Crypto

struct SyncPipeline {
    let db: Database
    let app: Application
    let fetcher: RepoFetcher

    init(db: Database, app: Application) {
        self.db = db
        self.app = app
        self.fetcher = RepoFetcher(app: app)
    }

    func run(projectId: UUID) async throws {
        let project = try await Project.find(projectId, on: db)
        guard let project = project else {
            throw PipelineError.projectNotFound
        }

        let repoConnections = try await project.$repoConnections.get(on: db)
        guard let connection = repoConnections.first else {
            throw PipelineError.noRepoConnection
        }

        var oauthToken: String?
        if let encrypted = connection.tokenEncrypted {
            oauthToken = try? TokenEncryption.decrypt(encrypted)
        }
        if oauthToken == nil {
            try await project.$account.load(on: db)
            if let encrypted = project.account.githubTokenEncrypted {
                oauthToken = try? TokenEncryption.decrypt(encrypted)
            }
        }

        let token: String?
        if let installationId = connection.githubInstallationId {
            token = try await GitHubAppInstallationTokenService.bearerTokenForGitHubREST(
                installationId: installationId,
                oauthToken: oauthToken ?? "",
                client: app.client,
                logger: app.logger,
                db: db
            )
        } else {
            token = oauthToken
        }

        let priorActiveReleaseId = project.activeReleaseId

        let release = Release(
            projectId: projectId,
            commitSha: "pending",
            status: "pending"
        )
        try await release.save(on: db)

        var tempCleanupPath: URL?
        defer {
            if let path = tempCleanupPath {
                try? FileManager.default.removeItem(at: path)
            }
        }

        do {
            let outcome = try await fetcher.fetch(
                owner: connection.repoOwner,
                repo: connection.repoName,
                ref: connection.defaultBranch,
                token: token
            )
            tempCleanupPath = outcome.tempRoot
            let extractPath = outcome.extractPath

            var resolvedSha = outcome.resolvedCommitSha
            if resolvedSha == nil {
                resolvedSha = try await fetcher.resolveCommitShaViaApi(
                    owner: connection.repoOwner,
                    repo: connection.repoName,
                    ref: connection.defaultBranch,
                    token: token
                )
            }
            let commitSha = resolvedSha ?? "unknown"
            release.commitSha = commitSha
            try await release.save(on: db)

            let repoRoot = try fetcher.resolveRepositoryRoot(extractPath: extractPath)
            let basePath = repoRoot.path
            let skillFiles = fetcher.findSkillFiles(in: repoRoot)
            let sourcePolicies = try SkillCanonicalCompiler.sourcePolicies(repoRoot: repoRoot)

            var allValid = true
            var errorSummary: String?
            var parsedSkills: [(ParsedSkill, SkillPackage)] = []
            var validationErrors: [[String: String]] = []
            var validationWarnings: [[String: String]] = []

            for fileURL in skillFiles {
                do {
                    let skill = try SkillParser.parse(fileURL: fileURL, basePath: basePath)
                    let report = Validator.validate(skill)
                    validationWarnings.append(contentsOf: report.warnings.map { ["path": $0.path, "message": $0.message] })

                    let validationStatus = report.isValid ? "valid" : "invalid"
                    let skillPackage = SkillPackage(
                        releaseId: release.id!,
                        path: skill.path,
                        name: skill.name,
                        description: skill.description,
                        hash: skill.hash,
                        validationStatus: validationStatus
                    )
                    try await skillPackage.save(on: db)
                    try await Self.persistPackageFiles(
                        package: skillPackage,
                        skillDirectory: fileURL.deletingLastPathComponent(),
                        db: db
                    )
                    parsedSkills.append((skill, skillPackage))

                    if !report.isValid {
                        allValid = false
                        let errMsgs = report.errors.map { "\($0.path): \($0.message)" }
                        errorSummary = (errorSummary.map { $0 + "\n" } ?? "") + errMsgs.joined(separator: "\n")
                        validationErrors.append(contentsOf: report.errors.map { ["path": $0.path, "message": $0.message] })
                    }

                    let exposureForIndex = SkillInference.inferExposureType(from: skill)
                    let indexSchema: String? = exposureForIndex == "tool"
                        ? CapabilitySchemaBuilder.toolInputSchemaJson(
                            description: skill.description,
                            summary: skill.description ?? String(skill.body.prefix(200))
                        )
                        : nil
                    let toolIndex = ToolIndex(
                        skillPackageId: skillPackage.id!,
                        toolName: MCPConstants.compiledCapabilityWireName(skillSlug: skill.name),
                        schemaJson: indexSchema,
                        handlerType: "platform"
                    )
                    try await toolIndex.save(on: db)
                } catch {
                    allValid = false
                    let rel = Self.relativeRepoPath(fileURL: fileURL, repoRootPath: basePath)
                    errorSummary = (errorSummary.map { $0 + "\n" } ?? "") + "\(rel): \(error.localizedDescription)"
                    validationErrors.append(["path": rel, "message": error.localizedDescription])
                }
            }

            let duplicateErrors = Validator.duplicateSkillIDErrors(parsedSkills.map { $0.0 })
            if !duplicateErrors.isEmpty {
                allValid = false
                validationErrors.append(contentsOf: duplicateErrors.map { ["path": $0.path, "message": $0.message] })
                errorSummary = (errorSummary.map { $0 + "\n" } ?? "")
                    + duplicateErrors.map { "\($0.path): \($0.message)" }.joined(separator: "\n")
            }

            let skillsToCompile = parsedSkills
            try await db.transaction { transaction in
                let compiler = Compiler(db: transaction)
                try await compiler.compile(
                    releaseId: release.id!,
                    skills: skillsToCompile,
                    sourcePolicies: sourcePolicies
                )
            }

            let bodyChangeCount = try await ReleaseMetadataCarryForward.apply(
                db: db,
                newReleaseId: release.id!,
                priorReleaseId: priorActiveReleaseId
            )

            let reportPayload: [String: Any] = [
                "is_valid": allValid,
                "errors": validationErrors,
                "warnings": validationWarnings
            ]
            let reportData = try JSONSerialization.data(withJSONObject: reportPayload)
            let reportJson = String(data: reportData, encoding: .utf8) ?? "{}"
            let validationReport = ValidationReportRecord(
                releaseId: release.id!,
                reportJson: reportJson
            )
            try await validationReport.save(on: db)

            release.status = allValid ? "ready" : "failed"
            release.errorSummary = errorSummary
            release.commitSha = commitSha
            release.skillBodyChangesCount = bodyChangeCount
            try await release.save(on: db)

            let compiledSkills = try await CompiledSkill.query(on: db)
                .filter(\.$release.$id == release.id!)
                .all()
            let allReady = allValid && compiledSkills.allSatisfy { $0.status == "ready" }
            if allReady {
                project.activeReleaseId = release.id
                try await project.save(on: db)
                app.mcpCatalogNotifications.bumpCatalog(for: projectId)
            }
        } catch {
            release.status = "failed"
            release.errorSummary = error.localizedDescription
            try await release.save(on: db)
            throw error
        }
    }
}

enum PipelineError: Error {
    case projectNotFound
    case noRepoConnection
}

extension SyncPipeline {
    static let maxPackageFileCount = 128
    static let maxPackageFileBytes = 256 * 1024
    static let maxPackageBytes = 2 * 1024 * 1024

    private struct PendingPackageFile: Sendable {
        let path: String
        let content: Data
        let contentType: String?
        let checksum: String
    }

    static func persistPackageFiles(package: SkillPackage, skillDirectory: URL, db: Database) async throws {
        guard let packageId = package.id else { return }
        let root = skillDirectory.standardizedFileURL
        let files = try packageFiles(skillDirectory: root)
        try await db.transaction { transaction in
            for file in files {
                let row = SkillPackageFile()
                row.$skillPackage.id = packageId
                row.path = file.path
                row.content = file.content
                row.contentType = file.contentType
                row.byteCount = file.content.count
                row.checksum = file.checksum
                try await row.save(on: transaction)
            }
        }
    }

    private static func packageFiles(skillDirectory root: URL) throws -> [PendingPackageFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var pending: [PendingPackageFile] = []
        var totalBytes = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.lastPathComponent != "SKILL.md" else { continue }
            let values = try fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
            )
            if values.isSymbolicLink == true { throw PackageFileIngestionError.unsafeEntry }
            if values.isDirectory == true {
                let nestedSkill = fileURL.appendingPathComponent("SKILL.md")
                if FileManager.default.fileExists(atPath: nestedSkill.path) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let resolved = fileURL.resolvingSymlinksInPath().standardizedFileURL
            let relative = try safePackageRelativePath(fileURL: resolved, root: root)
            let size = values.fileSize ?? 0
            guard size >= 0, size <= maxPackageFileBytes,
                  pending.count < maxPackageFileCount, totalBytes + size <= maxPackageBytes else {
                throw PackageFileIngestionError.boundsExceeded
            }
            let data = try Data(contentsOf: resolved, options: [.mappedIfSafe])
            guard data.count == size else { throw PackageFileIngestionError.fileChangedDuringRead }
            pending.append(.init(
                path: relative,
                content: data,
                contentType: contentType(for: relative),
                checksum: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            ))
            totalBytes += data.count
        }
        return pending
    }

    static func safePackageRelativePath(fileURL: URL, root: URL) throws -> String {
        let normalizedRoot = root.standardizedFileURL
        let normalizedFile = fileURL.standardizedFileURL
        guard normalizedFile.path.hasPrefix(normalizedRoot.path + "/") else {
            throw PackageFileIngestionError.unsafeEntry
        }
        let relative = String(normalizedFile.path.dropFirst(normalizedRoot.path.count + 1))
        guard !relative.isEmpty, !relative.split(separator: "/").contains("..") else {
            throw PackageFileIngestionError.unsafeEntry
        }
        return relative
    }

    private static func contentType(for path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "md": return "text/markdown"
        case "txt": return "text/plain"
        case "json": return "application/json"
        case "yaml", "yml": return "application/yaml"
        case "sh": return "text/x-shellscript"
        case "py": return "text/x-python"
        case "js", "mjs": return "text/javascript"
        case "ts": return "text/typescript"
        default: return nil
        }
    }

    fileprivate static func relativeRepoPath(fileURL: URL, repoRootPath: String) -> String {
        let p = fileURL.path
        let prefix = repoRootPath.hasSuffix("/") ? repoRootPath : repoRootPath + "/"
        if p.hasPrefix(prefix) {
            return String(p.dropFirst(prefix.count))
        }
        return fileURL.lastPathComponent
    }
}

enum PackageFileIngestionError: Error, Equatable {
    case boundsExceeded
    case fileChangedDuringRead
    case unsafeEntry
}
