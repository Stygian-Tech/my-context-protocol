import Fluent
import Vapor

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

        var tempExtractPath: URL?
        defer {
            if let path = tempExtractPath {
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
            tempExtractPath = outcome.extractPath
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

            let repoRoot = try fetcher.resolveRepositoryRoot(extractPath: extractPath)
            let basePath = repoRoot.path
            let skillFiles = fetcher.findSkillFiles(in: repoRoot)

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
                        toolName: "skill:\(skill.name)",
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

            let compiler = Compiler(db: db)
            try await compiler.compile(releaseId: release.id!, skills: parsedSkills)

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
    fileprivate static func relativeRepoPath(fileURL: URL, repoRootPath: String) -> String {
        let p = fileURL.path
        let prefix = repoRootPath.hasSuffix("/") ? repoRootPath : repoRootPath + "/"
        if p.hasPrefix(prefix) {
            return String(p.dropFirst(prefix.count))
        }
        return fileURL.lastPathComponent
    }
}
