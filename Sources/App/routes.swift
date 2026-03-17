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
    app.get("auth", "me") { req in
        try await AuthController.me(req: req)
    }
    app.post("auth", "logout") { req in
        try await AuthController.logout(req: req)
    }

    let protected = app.grouped(app.sessions.middleware, SessionAuthMiddleware())
    protected.get("projects") { req in
        try await ProjectController.list(req: req)
    }
    protected.post("projects") { req in
        try await ProjectController.create(req: req)
    }
    protected.get("projects", ":id") { req in
        try await ProjectController.get(req: req)
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
    protected.get("projects", ":id", "api-keys") { req in
        try await ProjectController.listApiKeys(req: req)
    }
    protected.post("projects", ":id", "api-keys") { req in
        try await ProjectController.createApiKey(req: req)
    }
    protected.get("projects", ":id", "request-logs") { req in
        try await ProjectController.listRequestLogs(req: req)
    }

    app.post("webhooks", "github") { req in
        try await WebhookController.github(req: req)
    }

    let mcpRoutes = app.grouped(ApiKeyMiddleware())
    mcpRoutes.post("mcp") { req in
        try await MCPController.handle(req: req)
    }
}
