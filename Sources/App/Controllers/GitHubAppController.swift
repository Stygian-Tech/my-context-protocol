import Fluent
import Vapor

enum GitHubAppController {
    private static func fallbackBaseForErrors(req: Request) -> String? {
        AppFrontendURL.defaultReturnToURL()
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

        let state: String
        do {
            state = try SignedOAuthState.signGitHubAppInstall(
                projectId: project.id!,
                returnTo: returnToOpt,
                owner: ownerOpt,
                repo: repoOpt
            )
        } catch SignedOAuthState.StateError.keyNotConfigured {
            throw Abort(.internalServerError, reason: "ENCRYPTION_KEY must be configured (32-byte base64) for OAuth state signing")
        } catch {
            throw Abort(.internalServerError, reason: "Failed to build GitHub App install state")
        }

        var components = URLComponents(string: "https://github.com/apps/\(slug)/installations/new")!
        components.queryItems = [URLQueryItem(name: "state", value: state)]
        guard let target = components.url else {
            throw Abort(.internalServerError, reason: "Invalid GitHub App install URL")
        }
        return req.redirect(to: target.absoluteString, redirectType: .normal)
    }

    /// Setup URL target after GitHub App installation. Requires session (same browser).
    static func installCallback(req: Request) async throws -> Response {
        let queryState = req.query[String.self, at: "state"]

        let projectId: UUID
        let returnToFromState: String?
        let ownerFromState: String?
        let repoFromState: String?
        do {
            guard let s = queryState, !s.isEmpty else {
                throw SignedOAuthState.StateError.invalidFormat
            }
            (projectId, returnToFromState, ownerFromState, repoFromState) = try SignedOAuthState.verifyGitHubAppInstall(state: s)
        } catch {
            req.logger.warning("GitHub App install state verify failed: \(error)")
            if let base = fallbackBaseForErrors(req: req) {
                return redirectWithQueryParam(req: req, base: base, param: "github_app_error", value: "invalid_state")
            }
            throw Abort(.badRequest, reason: "Invalid or expired install state")
        }

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

        guard let installationStr = req.query[String.self, at: "installation_id"],
              let installationId = Int64(installationStr) else {
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
        return req.redirect(to: success, redirectType: .normal)
    }
}
