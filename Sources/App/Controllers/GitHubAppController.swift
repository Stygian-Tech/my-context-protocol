import Fluent
import Vapor

enum GitHubAppController {
    /// Mirrors signed `state` so install can complete if GitHub omits or alters `state` (e.g. OAuth-during-install sends `code` instead).
    private static let sessionInstallProjectKey = "github_app_install_project_id"
    private static let sessionInstallReturnToKey = "github_app_install_return_to"
    private static let sessionInstallOwnerKey = "github_app_install_owner"
    private static let sessionInstallRepoKey = "github_app_install_repo"

    private static func fallbackBaseForErrors(req: Request) -> String? {
        AppFrontendURL.defaultReturnToURL()
    }

    private static func clearInstallSessionKeys(_ req: Request) {
        req.session.data[sessionInstallProjectKey] = nil
        req.session.data[sessionInstallReturnToKey] = nil
        req.session.data[sessionInstallOwnerKey] = nil
        req.session.data[sessionInstallRepoKey] = nil
    }

    private struct InstallSessionContext {
        let projectId: UUID
        let returnTo: String?
        let owner: String?
        let repo: String?
    }

    /// Read backup keys without clearing — clearing only on successful callback so failed attempts can retry.
    private static func peekSessionInstallContext(req: Request) -> InstallSessionContext? {
        guard let pidStr = req.session.data[sessionInstallProjectKey], !pidStr.isEmpty,
              let projectId = UUID(uuidString: pidStr) else {
            return nil
        }
        let returnTo = req.session.data[sessionInstallReturnToKey].flatMap { $0.isEmpty ? nil : $0 }
        let owner = req.session.data[sessionInstallOwnerKey].flatMap { $0.isEmpty ? nil : $0 }
        let repo = req.session.data[sessionInstallRepoKey].flatMap { $0.isEmpty ? nil : $0 }
        return InstallSessionContext(projectId: projectId, returnTo: returnTo, owner: owner, repo: repo)
    }

    private static func redirectWithQueryParam(
        req: Request,
        base: String,
        param: String,
        value: String
    ) -> Response {
        let sep = base.contains("?") ? "&" : "?"
        let enc = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        return req.redirect(to: base + sep + param + "=" + enc, redirectType: .normal)
    }

    private static func redirectInvalidState(req: Request) throws -> Response {
        if let base = fallbackBaseForErrors(req: req) {
            return redirectWithQueryParam(req: req, base: base, param: "github_app_error", value: "invalid_state")
        }
        throw Abort(.badRequest, reason: "Invalid or expired install state")
    }

    /// Starts the GitHub App installation flow. Requires session auth.
    static func installRedirect(req: Request) async throws -> Response {
        guard let account = req.storage[AccountKey.self], let account = account else {
            throw Abort(.unauthorized, reason: "Not authenticated")
        }
        guard let slug = Environment.get("GITHUB_APP_SLUG"), !slug.isEmpty else {
            throw Abort(.internalServerError, reason: "GITHUB_APP_SLUG not configured")
        }
        guard let projectId = req.query[UUID.self, at: "project_id"] else {
            throw Abort(.badRequest, reason: "project_id query parameter required")
        }
        guard let project = try await Project.query(on: req.db)
            .filter(\.$id == projectId)
            .filter(\.$account.$id == account.id!)
            .first() else {
            throw Abort(.notFound, reason: "Project not found")
        }

        let returnToOpt = try AppFrontendURL.validateOptionalReturnTo(req.query[String.self, at: "return_to"], for: req)

        let rawOwner = req.query[String.self, at: "owner"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawRepo = req.query[String.self, at: "repo"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerOpt = rawOwner.flatMap { $0.isEmpty ? nil : $0 }
        let repoOpt = rawRepo.flatMap { $0.isEmpty ? nil : $0 }

        // Short UUID `state` stored in DB — survives load balancers and avoids GitHub truncating long signed payloads.
        let intent = GitHubAppInstallIntent(
            projectId: project.id!,
            accountId: account.id!,
            returnTo: returnToOpt,
            owner: ownerOpt,
            repo: repoOpt,
            expiresAt: Date().addingTimeInterval(3600)
        )
        try await intent.save(on: req.db)
        guard let stateId = intent.id else {
            throw Abort(.internalServerError, reason: "Failed to create GitHub App install intent")
        }
        let state = stateId.uuidString

        // Session backup when GitHub omits `state` or for legacy debugging.
        req.session.data[Self.sessionInstallProjectKey] = project.id!.uuidString
        if let rt = returnToOpt {
            req.session.data[Self.sessionInstallReturnToKey] = rt
        } else {
            req.session.data[Self.sessionInstallReturnToKey] = nil
        }
        if let o = ownerOpt {
            req.session.data[Self.sessionInstallOwnerKey] = o
        } else {
            req.session.data[Self.sessionInstallOwnerKey] = nil
        }
        if let r = repoOpt {
            req.session.data[Self.sessionInstallRepoKey] = r
        } else {
            req.session.data[Self.sessionInstallRepoKey] = nil
        }

        var components = URLComponents(string: "https://github.com/apps/\(slug)/installations/new")!
        components.queryItems = [URLQueryItem(name: "state", value: state)]
        guard let target = components.url else {
            throw Abort(.internalServerError, reason: "Invalid GitHub App install URL")
        }
        return req.redirect(to: target.absoluteString, redirectType: .normal)
    }

    private struct ResolvedInstall {
        let projectId: UUID
        let returnTo: String?
        let owner: String?
        let repo: String?
    }

    /// Legacy signed `state` or session backup (when DB intent row is missing / expired). Does **not** clear session keys.
    private static func resolveInstallWithoutDbIntent(req: Request, queryState: String?) async throws -> ResolvedInstall? {
        if let s = queryState, !s.isEmpty {
            do {
                let (pid, rt, o, r) = try SignedOAuthState.verifyGitHubAppInstall(state: s)
                return ResolvedInstall(projectId: pid, returnTo: rt, owner: o, repo: r)
            } catch {
                req.logger.warning(
                    "GitHub App install state verify failed: \(error) (state length \(s.count)); trying session fallback"
                )
                guard let fallback = peekSessionInstallContext(req: req) else {
                    req.logger.warning("GitHub App install session fallback failed (no matching session install context)")
                    return nil
                }
                return ResolvedInstall(
                    projectId: fallback.projectId,
                    returnTo: fallback.returnTo,
                    owner: fallback.owner,
                    repo: fallback.repo
                )
            }
        }
        req.logger.warning("GitHub App install callback missing or empty state; trying session fallback")
        guard let fallback = peekSessionInstallContext(req: req) else {
            req.logger.warning(
                "GitHub App install session fallback failed (no session install context). If Setup URL uses a different host than where you log in, set SESSION_COOKIE_DOMAIN (e.g. .mycontextprotocol.dev) or use the app origin + /api/.../callback."
            )
            return nil
        }
        return ResolvedInstall(
            projectId: fallback.projectId,
            returnTo: fallback.returnTo,
            owner: fallback.owner,
            repo: fallback.repo
        )
    }

    /// When `state` is missing or invalid but `installation_id` is present: verify GitHub installation matches the session user, then use the latest non-expired intent for that account.
    private static func resolveViaInstallationAndLatestIntent(
        req: Request,
        installationId: Int64,
        account: Account
    ) async throws -> (ResolvedInstall, GitHubAppInstallIntent)? {
        guard (try? GitHubAppInstallationTokenService.loadPrivatePEM()) != nil,
              let cid = Environment.get("GITHUB_APP_CLIENT_ID"), !cid.isEmpty else {
            req.logger.warning("GitHub App install fallback: app JWT not configured")
            return nil
        }
        let gh: GitHubInstallationMeta
        do {
            gh = try await GitHubAppInstallationTokenService.fetchInstallation(
                installationId: installationId,
                client: req.client,
                logger: req.logger
            )
        } catch {
            req.logger.warning("GitHub App install fallback: GitHub installation fetch failed: \(error)")
            return nil
        }
        guard gh.accountType == "User", gh.accountId == account.githubId else {
            req.logger.warning(
                "GitHub App install fallback: installation account does not match session user (type=\(gh.accountType))"
            )
            return nil
        }
        guard let intent = try await GitHubAppInstallIntent.query(on: req.db)
            .filter(\.$account.$id == account.id!)
            .filter(\.$expiresAt > Date())
            .sort(\.$expiresAt, .descending)
            .first() else {
            req.logger.warning("GitHub App install fallback: no pending install intent for account")
            return nil
        }
        let resolved = ResolvedInstall(
            projectId: intent.$project.id,
            returnTo: intent.returnTo,
            owner: intent.owner,
            repo: intent.repo
        )
        return (resolved, intent)
    }

    /// Setup URL target after GitHub App installation. Requires session (same browser) unless intent + session match.
    static func installCallback(req: Request) async throws -> Response {
        let queryState = mergedInstallStateQuery(req)

        let installationIdOpt: Int64? = {
            if let s = req.query[String.self, at: "installation_id"], let v = Int64(s) {
                return v
            }
            return parseQueryParam(req.url.query, name: "installation_id").flatMap { Int64($0) }
        }()

        let resolved: ResolvedInstall
        /// Consumed only after session + project + installation_id succeed — never delete before auth, or retries get `invalid_state`.
        var dbIntentToFinalize: GitHubAppInstallIntent?

        if let s = queryState, !s.isEmpty, let uuid = UUID(uuidString: s),
           let intent = try await GitHubAppInstallIntent.find(uuid, on: req.db) {
            if intent.expiresAt <= Date() {
                try await intent.delete(on: req.db)
                req.logger.warning("GitHub App install intent expired (state id prefix \(s.prefix(8)))")
                guard let r = try await resolveInstallWithoutDbIntent(req: req, queryState: queryState) else {
                    return try redirectInvalidState(req: req)
                }
                resolved = r
            } else {
                resolved = ResolvedInstall(
                    projectId: intent.$project.id,
                    returnTo: intent.returnTo,
                    owner: intent.owner,
                    repo: intent.repo
                )
                dbIntentToFinalize = intent
            }
        } else {
            var r = try await resolveInstallWithoutDbIntent(req: req, queryState: queryState)
            if r == nil, let iid = installationIdOpt,
               let accountIdStr = req.session.data["accountId"],
               let accId = UUID(uuidString: accountIdStr),
               let acc = try await Account.find(accId, on: req.db),
               let pair = try await resolveViaInstallationAndLatestIntent(req: req, installationId: iid, account: acc) {
                r = pair.0
                dbIntentToFinalize = pair.1
                req.logger.info("GitHub App install resolved via installation_id + GitHub installation verification")
            }
            guard let final = r else {
                return try redirectInvalidState(req: req)
            }
            resolved = final
        }

        let projectId = resolved.projectId
        let returnToFromState = resolved.returnTo
        let ownerFromState = resolved.owner
        let repoFromState = resolved.repo

        let returnToEffective = returnToFromState ?? fallbackBaseForErrors(req: req) ?? ""

        guard let accountIdStr = req.session.data["accountId"],
              let accountId = UUID(uuidString: accountIdStr),
              let account = try await Account.find(accountId, on: req.db) else {
            if !returnToEffective.isEmpty {
                return redirectWithQueryParam(
                    req: req,
                    base: returnToEffective,
                    param: "github_app_error",
                    value: "not_authenticated"
                )
            }
            if let url = AppFrontendURL.loginErrorURL(code: "github_app_not_authenticated") {
                return req.redirect(to: url, redirectType: .normal)
            }
            throw Abort(.unauthorized, reason: "Not authenticated")
        }

        if let intent = dbIntentToFinalize, intent.$account.id != account.id {
            req.logger.warning("GitHub App install intent account mismatch (session vs intent row)")
            try await intent.delete(on: req.db)
            return try redirectInvalidState(req: req)
        }

        func redirectError(_ code: String) throws -> Response {
            let base = returnToEffective.isEmpty ? (fallbackBaseForErrors(req: req) ?? "") : returnToEffective
            if base.isEmpty {
                if let url = AppFrontendURL.loginErrorURL(code: "github_app_\(code)") {
                    return req.redirect(to: url, redirectType: .normal)
                }
                throw Abort(.badRequest, reason: "GitHub App install error: \(code)")
            }
            return redirectWithQueryParam(req: req, base: base, param: "github_app_error", value: code)
        }

        guard let installationId = installationIdOpt else {
            return try redirectError("missing_installation_id")
        }

        guard let project = try await Project.query(on: req.db)
            .filter(\.$id == projectId)
            .filter(\.$account.$id == account.id!)
            .first() else {
            return try redirectError("project_not_found")
        }

        let connections = try await project.$repoConnections.get(on: req.db)
        if let conn = connections.first {
            conn.githubInstallationId = installationId
            try await conn.save(on: req.db)
        } else {
            req.session.data["github_app_pending_installation_id"] = String(installationId)
            req.session.data["github_app_pending_installation_project_id"] = project.id!.uuidString
        }

        let successBase = returnToEffective.isEmpty ? (fallbackBaseForErrors(req: req) ?? "") : returnToEffective
        if successBase.isEmpty {
            if let url = AppFrontendURL.loginErrorURL(code: "github_app_missing_return") {
                return req.redirect(to: url, redirectType: .normal)
            }
            throw Abort(.internalServerError, reason: "FRONTEND_URL or CORS_ORIGIN must be set for install callback redirect")
        }
        var extra = "github_app_installed=1"
        if let o = ownerFromState, let r = repoFromState, !o.isEmpty, !r.isEmpty,
           let eo = o.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let er = r.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            extra += "&resume_owner=\(eo)&resume_repo=\(er)"
        }
        let success = successBase + (successBase.contains("?") ? "&" : "?") + extra

        if let intent = dbIntentToFinalize {
            try await intent.delete(on: req.db)
        }
        clearInstallSessionKeys(req)

        return req.redirect(to: success, redirectType: .normal)
    }

    /// Prefer `req.query`; if `state` is missing, parse `req.url.query` (some proxies differ).
    private static func mergedInstallStateQuery(_ req: Request) -> String? {
        let fromQuery = normalizeInstallStateQuery(req.query[String.self, at: "state"])
        if let fromQuery { return fromQuery }
        return normalizeInstallStateQuery(parseQueryParam(req.url.query, name: "state"))
    }

    private static func parseQueryParam(_ query: String?, name: String) -> String? {
        guard let query, !query.isEmpty else { return nil }
        return URLComponents(string: "https://placeholder.local?\(query)")?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
            .flatMap { $0.removingPercentEncoding ?? $0 }
    }

    /// Trim and strip accidental wrapping quotes from GitHub's `state` query value.
    private static func normalizeInstallStateQuery(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        if s.count >= 2, s.first == "\"", s.last == "\"" {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.count >= 2, s.first == "'", s.last == "'" {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s.isEmpty ? nil : s
    }
}
