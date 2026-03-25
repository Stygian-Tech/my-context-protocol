import Crypto
import Fluent
import Foundation
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
            created_at: formatDate(project.createdAt),
            custom_domain: project.customDomain,
            custom_domain_verified_at: project.customDomainVerifiedAt.map { formatDate($0) },
            mcp_url: McpUrlBuilder.publicMcpUrl(for: project)
        )
    }

    private static func allocateSubdomain(db: Database) async throws -> String {
        for _ in 0 ..< 32 {
            let candidate = TenantSubdomainGenerator.make()
            let taken = try await Project.query(on: db).filter(\.$subdomain == candidate).first() != nil
            if !taken { return candidate }
        }
        throw Abort(.internalServerError, reason: "Could not allocate subdomain")
    }

    private static func isValidSlug(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 128 else { return false }
        guard let r = try? NSRegularExpression(pattern: "^[a-z0-9]+(-[a-z0-9]+)*$") else { return false }
        let range = NSRange(s.startIndex..., in: s)
        return r.firstMatch(in: s, options: [], range: range) != nil
    }

    private static func syncRateConfig(isPro: Bool) -> (max: Int, windowSeconds: TimeInterval) {
        if isPro {
            let max = Int(Environment.get("SYNC_RATE_LIMIT_PRO_MAX") ?? "") ?? 60
            let w = TimeInterval(Int(Environment.get("SYNC_RATE_LIMIT_PRO_WINDOW_SECONDS") ?? "") ?? 3600)
            return (max, w)
        }
        let max = Int(Environment.get("SYNC_RATE_LIMIT_FREE_MAX") ?? "") ?? 10
        let w = TimeInterval(Int(Environment.get("SYNC_RATE_LIMIT_FREE_WINDOW_SECONDS") ?? "") ?? 3600)
        return (max, w)
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

    /// True when GitHub App + private key are configured so `connect-repo` can use installation tokens for Pro webhooks.
    private static func isGitHubAppConfiguredForProWebhooks() -> Bool {
        guard let slug = Environment.get("GITHUB_APP_SLUG"), !slug.isEmpty else { return false }
        guard let cid = Environment.get("GITHUB_APP_CLIENT_ID"), !cid.isEmpty else { return false }
        return (try? GitHubAppInstallationTokenService.loadPrivatePEM()) != nil
    }

    /// Public URL of the project page (same origin as `FRONTEND_URL` / `CORS_ORIGIN` — used for GitHub App install `return_to`).
    private static func frontendProjectPageUrl(projectId: UUID) throws -> String {
        guard let base = AppFrontendURL.normalizedBase() else {
            throw Abort(.internalServerError, reason: "FRONTEND_URL or CORS_ORIGIN must be set for GitHub App install flow")
        }
        return "\(base)/projects/\(projectId.uuidString)"
    }

    /// Browser navigates here (same-origin `/api` proxy) so session cookies apply; includes `owner`/`repo` so install state can resume connect.
    private static func buildGitHubAppInstallUrl(projectId: UUID, owner: String, repo: String, returnTo: String) throws -> String {
        guard let base = AppFrontendURL.normalizedBase() else {
            throw Abort(.internalServerError, reason: "FRONTEND_URL or CORS_ORIGIN must be set for GitHub App install flow")
        }
        guard let baseUrl = URL(string: base) else {
            throw Abort(.internalServerError, reason: "Invalid FRONTEND_URL or CORS_ORIGIN")
        }
        var components = URLComponents()
        components.scheme = baseUrl.scheme
        components.host = baseUrl.host
        components.port = baseUrl.port
        components.path = "/api/auth/github/app/install"
        components.queryItems = [
            URLQueryItem(name: "project_id", value: projectId.uuidString),
            URLQueryItem(name: "owner", value: owner),
            URLQueryItem(name: "repo", value: repo),
            URLQueryItem(name: "return_to", value: returnTo)
        ]
        guard let url = components.url else {
            throw Abort(.internalServerError, reason: "Could not build GitHub App install URL")
        }
        return url.absoluteString
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

    /// Active-release MCP catalog (tools, resources, prompts) for dashboard clients.
    static func catalog(req: Request) async throws -> ProjectCatalogResponse {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        let mcpUrl = McpUrlBuilder.publicMcpUrl(for: project)

        guard let releaseId = project.activeReleaseId else {
            return ProjectCatalogResponse(
                release_id: nil,
                release_status: nil,
                mcp_url: mcpUrl,
                tools: [],
                resources: [],
                prompts: []
            )
        }

        let release = try await Release.find(releaseId, on: req.db)
        let compiledIds = try await MCPCatalogService.readyCompiledSkillIds(releaseId: releaseId, db: req.db)

        let toolCaps = try await MCPCatalogService.capabilityDefs(
            compiledSkillIds: compiledIds,
            types: ["tool"],
            db: req.db
        )
        let resourceCaps = try await MCPCatalogService.capabilityDefs(
            compiledSkillIds: compiledIds,
            types: ["resource"],
            db: req.db
        )
        let promptCaps = try await MCPCatalogService.capabilityDefs(
            compiledSkillIds: compiledIds,
            types: ["prompt"],
            db: req.db
        )

        let tools = toolCaps.map { cap in
            ProjectCatalogTool(
                name: cap.capabilityName,
                description: cap.compiledSkill.summary,
                input_schema_json: cap.schemaJson
            )
        }

        let resources: [ProjectCatalogResource] = resourceCaps.compactMap { cap in
            guard let meta = CapabilitySchemaBuilder.parseResourceMeta(cap.schemaJson) else { return nil }
            return ProjectCatalogResource(
                uri: meta.uri,
                name: cap.compiledSkill.name,
                description: cap.compiledSkill.summary,
                mime_type: meta.mimeType
            )
        }

        let prompts = promptCaps.map { cap in
            ProjectCatalogPrompt(
                name: cap.capabilityName,
                description: cap.compiledSkill.summary
            )
        }

        return ProjectCatalogResponse(
            release_id: releaseId.uuidString,
            release_status: release?.status,
            mcp_url: mcpUrl,
            tools: tools,
            resources: resources,
            prompts: prompts
        )
    }

    static func create(req: Request) async throws -> ProjectResponse {
        let account = try requireAccount(req)
        struct CreateBody: Content {
            let name: String
            let slug: String
        }
        let body = try req.content.decode(CreateBody.self)
        let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = body.slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Abort(.badRequest, reason: "Name is required") }
        guard isValidSlug(slug) else {
            throw Abort(.badRequest, reason: "Invalid slug (lowercase letters, numbers, hyphens only)")
        }
        if try await Project.query(on: req.db)
            .filter(\.$account.$id == account.id!)
            .filter(\.$slug == slug)
            .first() != nil {
            throw Abort(.conflict, reason: "Slug already in use for this account")
        }

        let subdomain = try await allocateSubdomain(db: req.db)
        let project = Project(
            accountId: account.id!,
            name: name,
            slug: slug,
            subdomain: subdomain
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
            webhook_id: conn.webhookId,
            github_installation_configured: conn.githubInstallationId != nil
        )
    }

    static func connectRepo(req: Request) async throws -> Response {
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

        var pendingInstallation: Int64?
        if let ppid = req.session.data["github_app_pending_installation_project_id"],
           let pid = UUID(uuidString: ppid), pid == project.id!,
           let iidStr = req.session.data["github_app_pending_installation_id"],
           let iid = Int64(iidStr) {
            pendingInstallation = iid
            req.session.data["github_app_pending_installation_project_id"] = nil
            req.session.data["github_app_pending_installation_id"] = nil
        }

        let existing = try await project.$repoConnections.get(on: req.db)
        let existingFirst = existing.first
        let effectiveInstallationId: Int64? =
            pendingInstallation ?? existingFirst?.githubInstallationId ?? account.githubAppInstallationId

        // Pro: require GitHub App installation (when app + webhook env are configured) before we can use installation tokens.
        if account.hasProEntitlements,
           let wb = Environment.get("WEBHOOK_BASE_URL"), !wb.isEmpty,
           Self.isGitHubAppConfiguredForProWebhooks(),
           effectiveInstallationId == nil {
            let returnTo = try Self.frontendProjectPageUrl(projectId: project.id!)
            let installUrl = try Self.buildGitHubAppInstallUrl(
                projectId: project.id!,
                owner: body.owner,
                repo: body.repo,
                returnTo: returnTo
            )
            let payload = GitHubAppInstallRequiredResponse(
                reason: "github_app_install_required",
                install_url: installUrl
            )
            let response = try await payload.encodeResponse(for: req)
            response.status = .conflict
            response.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
            return response
        }

        if let first = existingFirst, let oldWebhookId = first.webhookId {
            let deleteToken = try await GitHubAppInstallationTokenService.bearerTokenForGitHubREST(
                installationId: first.githubInstallationId,
                oauthToken: token,
                client: req.client,
                logger: req.logger,
                db: req.db
            )
            try? await GitHubWebhookService.deleteWebhook(
                owner: first.repoOwner,
                repo: first.repoName,
                webhookId: oldWebhookId,
                token: deleteToken,
                client: req.client
            )
        }

        let verifyToken = try await GitHubAppInstallationTokenService.bearerTokenForGitHubREST(
            installationId: effectiveInstallationId,
            oauthToken: token,
            client: req.client,
            logger: req.logger,
            db: req.db
        )
        let userFallbackForVerify: String? = effectiveInstallationId != nil ? token : nil
        try await GitHubWebhookService.verifyRepoAccess(
            owner: body.owner,
            repo: body.repo,
            primaryToken: verifyToken,
            userFallbackToken: userFallbackForVerify,
            client: req.client,
            logger: req.logger
        )

        let isPro = account.hasProEntitlements
        var webhookId: String?
        var webhookSecret: String?
        if isPro {
            guard let baseURL = Environment.get("WEBHOOK_BASE_URL"), !baseURL.isEmpty else {
                throw Abort(.internalServerError, reason: "WEBHOOK_BASE_URL not configured")
            }
            let hookToken = try await GitHubAppInstallationTokenService.bearerTokenForGitHubREST(
                installationId: effectiveInstallationId,
                oauthToken: token,
                client: req.client,
                logger: req.logger,
                db: req.db
            )
            let created = try await GitHubWebhookService.createWebhook(
                owner: body.owner,
                repo: body.repo,
                token: hookToken,
                baseURL: baseURL,
                client: req.client
            )
            webhookId = created.webhookId
            webhookSecret = created.webhookSecret
        }

        let conn: RepoConnection
        if let first = existingFirst {
            first.repoOwner = body.owner
            first.repoName = body.repo
            first.defaultBranch = branch
            first.provider = "github"
            first.authType = "oauth"
            first.webhookId = webhookId
            first.webhookSecret = webhookSecret
            first.githubInstallationId = effectiveInstallationId
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
                webhookSecret: webhookSecret,
                githubInstallationId: effectiveInstallationId
            )
            try await conn.save(on: req.db)
        }
        let repoPayload = RepoConnectionResponse(
            project_id: project.id!.uuidString,
            provider: conn.provider,
            repo_owner: conn.repoOwner,
            repo_name: conn.repoName,
            default_branch: conn.defaultBranch,
            auth_type: conn.authType,
            webhook_id: conn.webhookId,
            github_installation_configured: conn.githubInstallationId != nil
        )
        return try await repoPayload.encodeResponse(for: req)
    }

    static func sync(req: Request) async throws -> Response {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        if !AppEnvironment.nonProductionBypassesActive {
            let cfg = syncRateConfig(isPro: account.hasProEntitlements)
            let allowed = req.application.syncRateLimiter.allow(
                accountId: account.id!,
                projectId: project.id!,
                maxRequests: cfg.max,
                windowSeconds: cfg.windowSeconds
            )
            guard allowed else {
                var headers = HTTPHeaders()
                headers.replaceOrAdd(name: .retryAfter, value: String(Int(ceil(cfg.windowSeconds))))
                return Response(status: .tooManyRequests, headers: headers)
            }
        }
        let pipeline = SyncPipeline(db: req.db, app: req.application)
        try await pipeline.run(projectId: project.id!)
        return Response(status: .noContent)
    }

    static func getCustomDomain(req: Request) async throws -> CustomDomainResponse {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        let verified = project.customDomainVerifiedAt != nil
        let token = verified ? nil : project.customDomainVerificationToken
        let instructions: String?
        if let host = project.customDomain, !host.isEmpty, let t = token, !t.isEmpty {
            instructions = "Add a TXT record on \(host) with value: \(t)"
        } else {
            instructions = nil
        }
        return CustomDomainResponse(
            hostname: project.customDomain,
            verified: verified,
            verification_token: token,
            instructions: instructions
        )
    }

    static func setCustomDomain(req: Request) async throws -> CustomDomainResponse {
        let account = try requireAccount(req)
        guard account.hasProEntitlements else {
            throw Abort(.paymentRequired, reason: "Custom domain requires Pro")
        }
        let project = try await requireProject(req, accountId: account.id!)
        struct Body: Content { let hostname: String }
        let body = try req.content.decode(Body.self)
        let raw = body.hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty, raw.count <= 253 else {
            throw Abort(.badRequest, reason: "Invalid hostname")
        }
        guard raw.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else {
            throw Abort(.badRequest, reason: "Invalid hostname characters")
        }
        let others = try await Project.query(on: req.db).filter(\.$customDomain == raw).all()
        if let conflict = others.first(where: { $0.id != project.id }) {
            _ = conflict
            throw Abort(.conflict, reason: "Domain is already registered to another project")
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        project.customDomain = raw
        project.customDomainVerificationToken = token
        project.customDomainVerifiedAt = nil
        try await project.save(on: req.db)
        return try await getCustomDomain(req: req)
    }

    static func verifyCustomDomain(req: Request) async throws -> CustomDomainResponse {
        let account = try requireAccount(req)
        guard account.hasProEntitlements else {
            throw Abort(.paymentRequired, reason: "Custom domain requires Pro")
        }
        let project = try await requireProject(req, accountId: account.id!)
        guard let host = project.customDomain, !host.isEmpty,
              let token = project.customDomainVerificationToken, !token.isEmpty else {
            throw Abort(.badRequest, reason: "Set a custom domain first")
        }
        let ok = try await DnsTxtVerifier.txtRecordsIncludeToken(hostname: host, token: token, client: req.client)
        guard ok else {
            throw Abort(.badRequest, reason: "TXT record not found or token mismatch")
        }
        project.customDomainVerifiedAt = Date()
        project.customDomainVerificationToken = nil
        try await project.save(on: req.db)
        return try await getCustomDomain(req: req)
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
        guard let release = release else {
            throw Abort(.notFound, reason: "Release not found")
        }
        guard release.status == "ready" else {
            throw Abort(.badRequest, reason: "Release must be ready before activation")
        }
        let compiledSkills = try await CompiledSkill.query(on: req.db)
            .filter(\.$release.$id == releaseId)
            .all()
        let allReady = compiledSkills.allSatisfy { $0.status == "ready" }
        guard allReady else {
            throw Abort(.badRequest, reason: "All compiled skills must be ready before activation")
        }
        project.activeReleaseId = releaseId
        try await project.save(on: req.db)
        return Response(status: .noContent)
    }

    static func listCompiledSkills(req: Request) async throws -> [CompiledSkillResponse] {
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
        let compiled = try await CompiledSkill.query(on: req.db)
            .filter(\.$release.$id == releaseId)
            .all()
        let skillIds = compiled.compactMap(\.id)
        var schemaBySkillId: [UUID: String] = [:]
        if !skillIds.isEmpty {
            let caps = try await CapabilityDef.query(on: req.db)
                .filter(\.$compiledSkill.$id ~~ skillIds)
                .all()
            for cap in caps {
                let sid = cap.$compiledSkill.id
                if schemaBySkillId[sid] == nil, let sj = cap.schemaJson, !sj.isEmpty {
                    schemaBySkillId[sid] = sj
                }
            }
        }
        return compiled.map { cs in
            let sid = cs.id!
            return CompiledSkillResponse(
                id: sid.uuidString,
                release_id: cs.$release.id.uuidString,
                skill_package_id: cs.$skillPackage.id.uuidString,
                path: cs.path,
                name: cs.name,
                summary: cs.summary,
                skill_body: cs.skillBody,
                schema_json: schemaBySkillId[sid],
                exposure_type: cs.exposureType,
                risk_level: cs.riskLevel,
                repo_specific: cs.repoSpecific,
                status: cs.status
            )
        }
    }

    static func updateCompiledSkill(req: Request) async throws -> CompiledSkillResponse {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        guard let releaseId = req.parameters.get("releaseId", as: UUID.self),
              let compiledSkillId = req.parameters.get("compiledSkillId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid release or compiled skill ID")
        }
        let release = try await Release.query(on: req.db)
            .filter(\.$id == releaseId)
            .filter(\.$project.$id == project.id!)
            .first()
        guard release != nil else {
            throw Abort(.notFound, reason: "Release not found")
        }
        guard let compiled = try await CompiledSkill.query(on: req.db)
            .filter(\.$id == compiledSkillId)
            .filter(\.$release.$id == releaseId)
            .first() else {
            throw Abort(.notFound, reason: "Compiled skill not found")
        }
        struct UpdateBody: Content {
            let exposure_type: String?
            let risk_level: String?
            let status: String?
            let summary: String?
            let skill_body: String?
            /// When `true`, `schema_json` is applied (empty string → rebuild default from summary/exposure). When `false` or omitted, custom JSON is preserved unless `exposure_type` or `summary` changes (those recompute defaults).
            let replace_schema: Bool?
            /// Replaces `capability_defs.schema_json` when `replace_schema` is true (must be valid JSON unless empty).
            let schema_json: String?
        }
        let body = try req.content.decode(UpdateBody.self)
        let exposureBefore = compiled.exposureType
        let summaryBefore = compiled.summary
        if let et = body.exposure_type, ["tool", "resource", "prompt"].contains(et) {
            compiled.exposureType = et
        }
        if let rl = body.risk_level, ["low", "medium", "high"].contains(rl) {
            compiled.riskLevel = rl
        }
        if let st = body.status, ["ready", "needs_review", "not_publishable"].contains(st) {
            compiled.status = st
        }
        if let summary = body.summary {
            let t = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            compiled.summary = t.isEmpty ? nil : t
        }
        if let bodySkill = body.skill_body {
            let t = bodySkill.trimmingCharacters(in: .whitespacesAndNewlines)
            compiled.skillBody = t.isEmpty ? nil : bodySkill
        }
        try await compiled.save(on: req.db)
        let exposureChanged = compiled.exposureType != exposureBefore
        let summaryChanged = compiled.summary != summaryBefore
        let caps = try await CapabilityDef.query(on: req.db)
            .filter(\.$compiledSkill.$id == compiled.id!)
            .all()
        let capType = compiled.exposureType == "guidance" ? "prompt" : compiled.exposureType
        let existingSchema = caps.first?.schemaJson
        let newSchema: String?
        if body.replace_schema == true, let raw = body.schema_json {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                newSchema = Compiler.schemaJson(forCapabilityType: capType, compiled: compiled)
            } else {
                guard (try? JSONSerialization.jsonObject(with: Data(t.utf8))) != nil else {
                    throw Abort(.badRequest, reason: "schema_json must be valid JSON")
                }
                newSchema = t
            }
        } else if exposureChanged || summaryChanged {
            newSchema = Compiler.schemaJson(forCapabilityType: capType, compiled: compiled)
        } else {
            newSchema = existingSchema ?? Compiler.schemaJson(forCapabilityType: capType, compiled: compiled)
        }
        for cap in caps {
            cap.type = capType
            cap.schemaJson = newSchema
            try await cap.save(on: req.db)
        }
        return CompiledSkillResponse(
            id: compiled.id!.uuidString,
            release_id: compiled.$release.id.uuidString,
            skill_package_id: compiled.$skillPackage.id.uuidString,
            path: compiled.path,
            name: compiled.name,
            summary: compiled.summary,
            skill_body: compiled.skillBody,
            schema_json: newSchema,
            exposure_type: compiled.exposureType,
            risk_level: compiled.riskLevel,
            repo_specific: compiled.repoSpecific,
            status: compiled.status
        )
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
        let limit = min(req.query[Int.self, at: "limit"] ?? 50, 200)
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
                error_code: log.errorCode,
                error_message: log.errorMessage
            )
        }
    }

    /// Structured validation errors for a release (`skill_packages` / pipeline report).
    static func releaseValidation(req: Request) async throws -> ReleaseValidationResponse {
        let account = try requireAccount(req)
        let project = try await requireProject(req, accountId: account.id!)
        guard let releaseId = req.parameters.get("releaseId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid release ID")
        }
        let release = try await Release.query(on: req.db)
            .filter(\.$id == releaseId)
            .filter(\.$project.$id == project.id!)
            .first()
        guard let release = release else {
            throw Abort(.notFound, reason: "Release not found")
        }
        guard let record = try await ValidationReportRecord.query(on: req.db)
            .filter(\.$release.$id == releaseId)
            .first() else {
            if release.status == "failed" {
                let trimmed = release.errorSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let message = trimmed.isEmpty
                    ? "Release failed; no structured validation report was stored."
                    : trimmed
                return ReleaseValidationResponse(is_valid: false, errors: [
                    ValidationErrorEntry(path: "release", message: message)
                ])
            }
            return ReleaseValidationResponse(is_valid: true, errors: [])
        }
        guard let data = record.reportJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ReleaseValidationResponse(is_valid: false, errors: [
                ValidationErrorEntry(path: "report", message: "Could not parse validation report JSON")
            ])
        }
        let isValid = (obj["is_valid"] as? Bool) ?? false
        let rawErrors = (obj["errors"] as? [[String: Any]]) ?? []
        let errors: [ValidationErrorEntry] = rawErrors.compactMap { e in
            guard let path = e["path"] as? String else { return nil }
            let message = (e["message"] as? String) ?? ""
            return ValidationErrorEntry(path: path, message: message)
        }
        return ReleaseValidationResponse(is_valid: isValid, errors: errors)
    }
}
