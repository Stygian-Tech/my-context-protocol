import Vapor

func routes(_ app: Application) throws {
    app.get { _ in
        "MyContextProtocol"
    }

    app.get("health") { _ in
        "ok"
    }

    app.post("auth", "login") { req in
        try await AuthController.login(req: req)
    }
    app.post("auth", "logout") { req in
        try await AuthController.logout(req: req)
    }

    let protected = app.grouped(app.sessions.middleware, SessionAuthMiddleware())
    protected.post("sync") { req in
        try await SyncController.trigger(req: req)
    }
    protected.post("api-keys") { req in
        try await ApiKeyController.create(req: req)
    }

    app.post("webhooks", "github") { req in
        try await WebhookController.github(req: req)
    }

    let mcpRoutes = app.grouped(ApiKeyMiddleware())
    mcpRoutes.post("mcp") { req in
        try await MCPController.handle(req: req)
    }
}
