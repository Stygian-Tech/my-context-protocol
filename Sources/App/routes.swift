import Vapor

func routes(_ app: Application) throws {
    app.get { _ in
        "MyContextProtocol"
    }

    app.get("health") { _ in
        "ok"
    }

    app.get("auth", "github") { req in
        try await AuthController.githubInitiate(req: req)
    }
    app.get("auth", "github", "callback") { req in
        try await AuthController.githubCallback(req: req)
    }
    app.get("auth", "github", "app", "callback") { req in
        try await GitHubAppController.installCallback(req: req)
    }
    app.get("auth", "me") { req in
        try await AuthController.me(req: req)
    }
    app.get("auth", "confirm") { req in
        try await AuthController.confirm(req: req)
    }
    app.post("auth", "logout") { req in
        try await AuthController.logout(req: req)
    }

    let protected = app.grouped(app.sessions.middleware, SessionAuthMiddleware())
    protected.get("dashboard", "summary") { req in
        try await ProjectController.accountDashboardSummary(req: req)
    }
    protected.get("projects") { req in
        try await ProjectController.list(req: req)
    }
    protected.post("projects") { req in
        try await ProjectController.create(req: req)
    }
    protected.get("projects", ":id", "dashboard", "summary") { req in
        try await ProjectController.projectDashboardSummary(req: req)
    }
    protected.get("projects", ":id") { req in
        try await ProjectController.get(req: req)
    }
    protected.get("projects", ":id", "catalog") { req in
        try await ProjectController.catalog(req: req)
    }
    protected.get("projects", ":id", "repo-connection") { req in
        try await ProjectController.getRepoConnection(req: req)
    }
    protected.post("projects", ":id", "connect-repo") { req in
        try await ProjectController.connectRepo(req: req)
    }
    protected.post("projects", ":id", "sync") { req in
        try await ProjectController.sync(req: req)
    }
    protected.get("projects", ":id", "releases") { req in
        try await ProjectController.listReleases(req: req)
    }
    protected.post("projects", ":id", "releases", ":releaseId", "activate") { req in
        try await ProjectController.activateRelease(req: req)
    }
    protected.get("projects", ":id", "releases", ":releaseId", "validation") { req in
        try await ProjectController.releaseValidation(req: req)
    }
    protected.get("projects", ":id", "releases", ":releaseId", "compiled-skills") { req in
        try await ProjectController.listCompiledSkills(req: req)
    }
    protected.patch("projects", ":id", "releases", ":releaseId", "compiled-skills", ":compiledSkillId") { req in
        try await ProjectController.updateCompiledSkill(req: req)
    }
    protected.get("projects", ":id", "api-keys") { req in
        try await ProjectController.listApiKeys(req: req)
    }
    protected.post("projects", ":id", "api-keys") { req in
        try await ProjectController.createApiKey(req: req)
    }
    protected.get("projects", ":id", "request-logs") { req in
        try await ProjectController.listRequestLogs(req: req)
    }
    protected.get("projects", ":id", "custom-domain") { req in
        try await ProjectController.getCustomDomain(req: req)
    }
    protected.post("projects", ":id", "custom-domain") { req in
        try await ProjectController.setCustomDomain(req: req)
    }
    protected.post("projects", ":id", "custom-domain", "verify") { req in
        try await ProjectController.verifyCustomDomain(req: req)
    }
    protected.post("billing", "checkout-session") { req in
        try await BillingController.createCheckoutSession(req: req)
    }
    protected.post("billing", "portal-session") { req in
        try await BillingController.createPortalSession(req: req)
    }
    protected.get("github", "repos") { req in
        try await AuthController.listGithubRepos(req: req)
    }
    protected.get("auth", "github", "app", "install") { req in
        try await GitHubAppController.installRedirect(req: req)
    }

    app.post("webhooks", "github") { req in
        try await WebhookController.github(req: req)
    }
    app.post("webhooks", "github-app") { req in
        try await GitHubAppWebhookController.handle(req: req)
    }
    app.post("webhooks", "stripe") { req in
        try await StripeWebhookController.handle(req: req)
    }

    let mcpRoutes = app.grouped(TenantHostMiddleware(), ApiKeyMiddleware())
    McpRoutePath.registerPost(on: mcpRoutes) { req in
        try await MCPController.handle(req: req)
    }
}
