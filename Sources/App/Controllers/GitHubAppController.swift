import Fluent
import Vapor

enum GitHubAppController {
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

        let state = UUID().uuidString
        req.session.data["github_app_install_state"] = state
        req.session.data["github_app_install_project_id"] = project.id!.uuidString
        let returnTo = req.query[String.self, at: "return_to"] ?? ""
        req.session.data["github_app_install_return_to"] = returnTo

        var components = URLComponents(string: "https://github.com/apps/\(slug)/installations/new")!
        components.queryItems = [URLQueryItem(name: "state", value: state)]
        guard let target = components.url else {
            throw Abort(.internalServerError, reason: "Invalid GitHub App install URL")
        }
        return req.redirect(to: target.absoluteString, redirectType: .normal)
    }

    /// Setup URL target after GitHub App installation. Requires session (same browser).
    static func installCallback(req: Request) async throws -> Response {
        let returnTo = req.session.data["github_app_install_return_to"].flatMap { $0.isEmpty ? nil : $0 } ?? ""

        let queryState = req.query[String.self, at: "state"]
        let storedState = req.session.data["github_app_install_state"]
        let projectIdStr = req.session.data["github_app_install_project_id"]

        req.session.data["github_app_install_state"] = nil
        req.session.data["github_app_install_project_id"] = nil
        req.session.data["github_app_install_return_to"] = nil

        guard let accountIdStr = req.session.data["accountId"],
              let accountId = UUID(uuidString: accountIdStr),
              let account = try await Account.find(accountId, on: req.db) else {
            let err = returnTo.isEmpty ? "http://localhost:3000/?github_app_error=not_authenticated"
                : returnTo + (returnTo.contains("?") ? "&" : "?") + "github_app_error=not_authenticated"
            return req.redirect(to: err, redirectType: .normal)
        }

        func redirectError(_ code: String) -> Response {
            let base = returnTo.isEmpty ? "http://localhost:3000/" : returnTo
            return req.redirect(to: base + (base.contains("?") ? "&" : "?") + "github_app_error=\(code)", redirectType: .normal)
        }

        guard let queryState = queryState, let storedState = storedState, queryState == storedState, !queryState.isEmpty else {
            return redirectError("invalid_state")
        }

        guard let installationStr = req.query[String.self, at: "installation_id"],
              let installationId = Int64(installationStr) else {
            return redirectError("missing_installation_id")
        }

        guard let projectIdStr = projectIdStr, let projectId = UUID(uuidString: projectIdStr) else {
            return redirectError("missing_project")
        }

        guard let project = try await Project.query(on: req.db)
            .filter(\.$id == projectId)
            .filter(\.$account.$id == account.id!)
            .first() else {
            return redirectError("project_not_found")
        }

        let connections = try await project.$repoConnections.get(on: req.db)
        if let conn = connections.first {
            conn.githubInstallationId = installationId
            try await conn.save(on: req.db)
        } else {
            req.session.data["github_app_pending_installation_id"] = String(installationId)
            req.session.data["github_app_pending_installation_project_id"] = project.id!.uuidString
        }

        let successBase = returnTo.isEmpty ? "http://localhost:3000/" : returnTo
        let success = successBase + (successBase.contains("?") ? "&" : "?") + "github_app_installed=1"
        return req.redirect(to: success, redirectType: .normal)
    }
}
