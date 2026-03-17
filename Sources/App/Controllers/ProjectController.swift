import Crypto
import Fluent
import Vapor

struct ProjectController {
    private static func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func projectResponse(_ project: Project) -> ProjectResponse {
        ProjectResponse(
            id: project.id!.uuidString,
            account_id: project.$account.id.uuidString,
            name: project.name,
            slug: project.slug,
            subdomain: project.subdomain ?? "",
            created_at: formatDate(project.createdAt)
        )
    }

    private static func requireAccount(_ req: Request) throws -> Account {
        guard let account = req.storage[AccountKey.self], let account = account else {
            throw Abort(.unauthorized, reason: "Not authenticated")
        }
        return account
    }

    private static func requireProject(_ req: Request, accountId: UUID) async throws -> Project {
        guard let projectId = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid project ID")
        }
        guard let project = try await Project.query(on: req.db)
            .filter(\.$id == projectId)
            .filter(\.$account.$id == accountId)
            .first() else {
            throw Abort(.notFound, reason: "Project not found")
        }
        return project
    }

    static func list(req: Request) async throws -> [ProjectResponse] {
        let account = try requireAccount(req)
        let projects = try await Project.query(on: req.db)
            .filter(\.$account.$id == account.id!)
            .all()
        return projects.map { projectResponse($0) }
    }

    static func get(req: Request) async throws -> ProjectResponse {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        return projectResponse(project)
    }

    static func create(req: Request) async throws -> ProjectResponse {
        let account = try requireAccount(req)
        struct CreateBody: Content {
            let name: String
            let slug: String
            let subdomain: String?
        }
        let body = try req.content.decode(CreateBody.self)
        let subdomain = body.subdomain ?? ""

        let project = Project(
            accountId: account.id!,
            name: body.name,
            slug: body.slug,
            subdomain: subdomain.isEmpty ? nil : subdomain
        )
        try await project.save(on: req.db)
        return projectResponse(project)
    }

    static func getRepoConnection(req: Request) async throws -> RepoConnectionResponse {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        let connections = try await project.$repoConnections.get(on: req.db)
        guard let conn = connections.first else {
            throw Abort(.notFound, reason: "No repo connected")
        }
        return RepoConnectionResponse(
            project_id: project.id!.uuidString,
            provider: conn.provider,
            repo_owner: conn.repoOwner,
            repo_name: conn.repoName,
            default_branch: conn.defaultBranch,
            auth_type: conn.authType,
            webhook_id: conn.webhookId
        )
    }

    static func connectRepo(req: Request) async throws -> RepoConnectionResponse {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        struct ConnectBody: Content {
            let owner: String
            let repo: String
            let branch: String?
        }
        let body = try req.content.decode(ConnectBody.self)
        let branch = body.branch ?? "main"

        guard let encrypted = account.githubTokenEncrypted,
              let token = try? TokenEncryption.decrypt(encrypted), !token.isEmpty else {
            throw Abort(.badRequest, reason: "No GitHub token. Re-authorize with repo scope.")
        }

        try await GitHubWebhookService.verifyRepoAccess(
            owner: body.owner,
            repo: body.repo,
            token: token,
            client: req.client
        )

        let existing = try await project.$repoConnections.get(on: req.db)
        if let first = existing.first, let oldWebhookId = first.webhookId {
            try? await GitHubWebhookService.deleteWebhook(
                owner: first.repoOwner,
                repo: first.repoName,
                webhookId: oldWebhookId,
                token: token,
                client: req.client
            )
        }

        guard let baseURL = Environment.get("WEBHOOK_BASE_URL"), !baseURL.isEmpty else {
            throw Abort(.internalServerError, reason: "WEBHOOK_BASE_URL not configured")
        }

        let (webhookId, webhookSecret) = try await GitHubWebhookService.createWebhook(
            owner: body.owner,
            repo: body.repo,
            token: token,
            baseURL: baseURL,
            client: req.client
        )

        let conn: RepoConnection
        if let first = existing.first {
            first.repoOwner = body.owner
            first.repoName = body.repo
            first.defaultBranch = branch
            first.provider = "github"
            first.authType = "oauth"
            first.webhookId = webhookId
            first.webhookSecret = webhookSecret
            try await first.save(on: req.db)
            conn = first
        } else {
            conn = RepoConnection(
                projectId: project.id!,
                provider: "github",
                repoOwner: body.owner,
                repoName: body.repo,
                defaultBranch: branch,
                authType: "oauth",
                webhookId: webhookId,
                webhookSecret: webhookSecret
            )
            try await conn.save(on: req.db)
        }
        return RepoConnectionResponse(
            project_id: project.id!.uuidString,
            provider: conn.provider,
            repo_owner: conn.repoOwner,
            repo_name: conn.repoName,
            default_branch: conn.defaultBranch,
            auth_type: conn.authType,
            webhook_id: conn.webhookId
        )
    }

    static func sync(req: Request) async throws -> Response {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        let pipeline = SyncPipeline(db: req.db, app: req.application)
        try await pipeline.run(projectId: project.id!)
        return Response(status: .noContent)
    }

    static func listReleases(req: Request) async throws -> [ReleaseResponse] {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        let releases = try await project.$releases.get(on: req.db)
        return releases.map { r in
            ReleaseResponse(
                id: r.id!.uuidString,
                project_id: project.id!.uuidString,
                commit_sha: r.commitSha,
                status: r.status,
                created_at: formatDate(r.createdAt),
                error_summary: r.errorSummary
            )
        }
    }

    static func activateRelease(req: Request) async throws -> Response {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        guard let releaseId = req.parameters.get("releaseId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid release ID")
        }
        let release = try await Release.query(on: req.db)
            .filter(\.$id == releaseId)
            .filter(\.$project.$id == project.id!)
            .first()
        guard release != nil else {
            throw Abort(.notFound, reason: "Release not found")
        }
        project.activeReleaseId = releaseId
        try await project.save(on: req.db)
        return Response(status: .noContent)
    }

    static func listApiKeys(req: Request) async throws -> [ApiKeyResponse] {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        let keys = try await project.$apiKeys.get(on: req.db)
        return keys.map { k in
            ApiKeyResponse(
                id: k.id!.uuidString,
                project_id: project.id!.uuidString,
                key_prefix: k.keyPrefix,
                status: k.status,
                created_at: formatDate(k.createdAt),
                last_used_at: k.lastUsedAt.map { formatDate($0) }
            )
        }
    }

    static func createApiKey(req: Request) async throws -> ApiKeyCreateResponse {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        let rawKey = "mcp_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let hash = SHA256.hash(data: Data(rawKey.utf8))
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        let prefix = String(rawKey.prefix(12))

        let apiKey = ApiKey(
            projectId: project.id!,
            keyPrefix: prefix,
            keyHash: hashString,
            status: "active"
        )
        try await apiKey.save(on: req.db)
        return ApiKeyCreateResponse(key: rawKey, prefix: prefix)
    }

    static func listRequestLogs(req: Request) async throws -> [RequestLogResponse] {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        let limit = min(req.query[Int.self, at: "limit"] ?? 50, 100)
        let offset = req.query[Int.self, at: "offset"] ?? 0

        let logs = try await RequestLog.query(on: req.db)
            .filter(\.$project.$id == project.id!)
            .sort(\.$timestamp, .descending)
            .limit(limit)
            .offset(offset)
            .all()

        return logs.map { log in
            let statusInt = Int(log.status) ?? 0
            return RequestLogResponse(
                id: log.id!.uuidString,
                project_id: project.id!.uuidString,
                release_id: log.$release.id.map { $0.uuidString },
                timestamp: formatDate(log.timestamp),
                client_id: log.clientId,
                method: log.method,
                latency_ms: log.latencyMs,
                status: statusInt,
                error_code: log.errorCode
            )
        }
    }
}
