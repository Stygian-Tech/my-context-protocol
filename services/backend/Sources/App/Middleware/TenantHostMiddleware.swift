import Fluent
import Vapor

/// Resolves `Project` from `Host` when `SAAS_MCP_BASE_DOMAIN` is set (subdomain) or from verified custom domain.
struct ResolvedHostProjectKey: StorageKey {
    typealias Value = Project
}

struct TenantHostMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let host = RequestPublicOrigin.routingHostname(for: request) else {
            request.logger.devTrace("tenant_host no Host header path=\(request.url.path)")
            return try await next.respond(to: request)
        }

        if let byCustom = try await Project.query(on: request.db).filter(\.$customDomain == host).first(),
           byCustom.customDomainVerifiedAt != nil {
            request.storage[ResolvedHostProjectKey.self] = byCustom
            request.logger.devTrace("tenant_host resolved=verified_custom_domain host=\(host) projectId=\(byCustom.id?.uuidString ?? "nil")")
            return try await next.respond(to: request)
        }

        guard let base = Environment.get("SAAS_MCP_BASE_DOMAIN"), !base.isEmpty else {
            request.logger.devTrace("tenant_host no_saas_base host=\(host) path=\(request.url.path)")
            return try await next.respond(to: request)
        }
        let baseLower = base.lowercased()
        guard host.hasSuffix("." + baseLower), host.count > baseLower.count + 1 else {
            request.logger.devTrace("tenant_host not_subdomain_of base=\(baseLower) host=\(host)")
            return try await next.respond(to: request)
        }
        let prefix = String(host.dropLast(baseLower.count + 1))
        guard !prefix.isEmpty,
              let project = try await Project.query(on: request.db).filter(\.$subdomain == prefix).first() else {
            request.logger.devTrace("tenant_host subdomain_unresolved prefix=\(prefix)")
            return try await next.respond(to: request)
        }
        request.storage[ResolvedHostProjectKey.self] = project
        request.logger.devTrace("tenant_host resolved=subdomain prefix=\(prefix) projectId=\(project.id?.uuidString ?? "nil")")
        return try await next.respond(to: request)
    }
}
