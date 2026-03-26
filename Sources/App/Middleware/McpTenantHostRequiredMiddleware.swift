import Vapor

/// Ensures MCP is only served when the Host maps to a project (subdomain or verified custom domain).
struct McpTenantHostRequiredMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard AppEnvironment.requireMcpTenantHostBinding else {
            return try await next.respond(to: request)
        }
        guard let project = request.storage[ResolvedHostProjectKey.self], project.id != nil else {
            return Response(status: .forbidden, body: .init(string: "MCP is only available on your project MCP hostname"))
        }
        return try await next.respond(to: request)
    }
}
