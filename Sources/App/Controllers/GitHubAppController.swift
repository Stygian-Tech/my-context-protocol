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

    /// Reads and clears session keys set in `installRedirect` when signed `state` cannot be verified.
    private static func loadInstallContextFromSession(req: Request) -> InstallSessionContext? {
        guard let pidStr = req.session.data[sessionInstallProjectKey], !pidStr.isEmpty,
              let projectId = UUID(uuidString: pidStr) else {
            return nil
        }
        let returnTo = req.session.data[sessionInstallReturnToKey].flatMap { $0.isEmpty ? nil : $0 }
        let owner = req.session.data[sessionInstallOwnerKey].flatMap { $0.isEmpty ? nil : $0 }
        let repo = req.session.data[sessionInstallRepoKey].flatMap { $0.isEmpty ? nil : $0 }
        clearInstallSessionKeys(req)
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

        // Session backup: GitHub sometimes does not echo `state` back (e.g. OAuth during install uses `code` only).
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

    /// Setup URL target after GitHub App installation. Requires session (same browser).
    static func installCallback(req: Request) async throws -> Response {
        let queryState = req.query[String.self, at: "state"]

        let projectId: UUID
        let returnToFromState: String?
        let ownerFromState: String?
        let repoFromState: String?

        if let s = queryState, !s.isEmpty {
            do {
                (projectId, returnToFromState, ownerFromState, repoFromState) = try SignedOAuthState.verifyGitHubAppInstall(state: s)
                clearInstallSessionKeys(req)
            } catch {
                req.logger.warning(
                    "GitHub App install state verify failed: \(error) (state length \(s.count)); trying session fallback"
                )
                guard let fallback = self.loadInstallContextFromSession(req: req) else {
                    req.logger.warning("GitHub App install session fallback failed (no matching session install context)")
                    if let base = fallbackBaseForErrors(req: req) {
                        return redirectWithQueryParam(req: req, base: base, param: "github_app_error", value: "invalid_state")
                    }
                    throw Abort(.badRequest, reason: "Invalid or expired install state")
                }
                projectId = fallback.projectId
                returnToFromState = fallback.returnTo
                ownerFromState = fallback.owner
                repoFromState = fallback.repo
            }
        } else {
            req.logger.warning("GitHub App install callback missing or empty state; trying session fallback")
            guard let fallback = self.loadInstallContextFromSession(req: req) else {
                req.logger.warning(
                    "GitHub App install session fallback failed (no session install context). If Setup URL uses a different host than where you log in, set SESSION_COOKIE_DOMAIN (e.g. .mycontextprotocol.dev) or use the app origin + /api/.../callback."
                )
                if let base = fallbackBaseForErrors(req: req) {
                    return redirectWithQueryParam(req: req, base: base, param: "github_app_error", value: "invalid_state")
                }
                throw Abort(.badRequest, reason: "Invalid or expired install state")
            }
            projectId = fallback.projectId
            returnToFromState = fallback.returnTo
            ownerFromState = fallback.owner
            repoFromState = fallback.repo
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
