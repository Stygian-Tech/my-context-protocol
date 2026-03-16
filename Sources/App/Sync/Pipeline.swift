import Fluent
import Vapor

struct SyncPipeline {
    let db: Database
    let fetcher: RepoFetcher

    init(db: Database, app: Application) {
        self.db = db
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
            let extractPath = try await fetcher.fetch(
                owner: connection.repoOwner,
                repo: connection.repoName,
                ref: connection.defaultBranch
            )
            tempExtractPath = extractPath

            let basePath = extractPath.path
            let skillFiles = fetcher.findSkillFiles(in: extractPath)

            var allValid = true
            var errorSummary: String?

            for fileURL in skillFiles {
                do {
                    let skill = try SkillParser.parse(fileURL: fileURL, basePath: basePath)
                    let report = Validator.validate(skill)

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

                    if !report.isValid {
                        allValid = false
                        let errMsgs = report.errors.map { "\($0.path): \($0.message)" }
                        errorSummary = (errorSummary.map { $0 + "\n" } ?? "") + errMsgs.joined(separator: "\n")
                    }

                    let toolIndex = ToolIndex(
                        skillPackageId: skillPackage.id!,
                        toolName: "skill:\(skill.name)",
                        schemaJson: nil,
                        handlerType: "platform"
                    )
                    try await toolIndex.save(on: db)
                } catch {
                    allValid = false
                    errorSummary = (errorSummary.map { $0 + "\n" } ?? "") + "\(fileURL.path): \(error.localizedDescription)"
                }
            }

            release.status = allValid ? "ready" : "failed"
            release.errorSummary = errorSummary
            release.commitSha = "latest"
            try await release.save(on: db)

            if allValid {
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
