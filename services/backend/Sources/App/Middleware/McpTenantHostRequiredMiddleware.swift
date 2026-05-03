import Vapor

/// Ensures MCP is only served when the Host maps to a project (subdomain or verified custom domain).
struct McpTenantHostRequiredMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard AppEnvironment.requireMcpTenantHostBinding else {
            request.logger.devTrace("mcp_tenant_host requirement=off")
            return try await next.respond(to: request)
        }
        guard let project = request.storage[ResolvedHostProjectKey.self], project.id != nil else {
            request.logger.devTrace("mcp_tenant_host rejected=no_resolved_project")
            return Response(status: .forbidden, body: .init(string: "MCP is only available on your project MCP hostname"))
        }
        request.logger.devTrace("mcp_tenant_host ok projectId=\(project.id!.uuidString)")
        return try await next.respond(to: request)
    }
}
