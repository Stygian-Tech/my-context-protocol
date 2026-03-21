import Fluent
import Vapor

/// Resolves `Project` from `Host` when `SAAS_MCP_BASE_DOMAIN` is set (subdomain) or from verified custom domain.
struct ResolvedHostProjectKey: StorageKey {
    typealias Value = Project
}

struct TenantHostMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let hostFull = request.headers.first(name: .host) else {
            return try await next.respond(to: request)
        }
        let host = String(hostFull.split(separator: ":").first ?? Substring(hostFull)).lowercased()

        if let byCustom = try await Project.query(on: request.db).filter(\.$customDomain == host).first(),
           byCustom.customDomainVerifiedAt != nil {
            request.storage[ResolvedHostProjectKey.self] = byCustom
            return try await next.respond(to: request)
        }

        guard let base = Environment.get("SAAS_MCP_BASE_DOMAIN"), !base.isEmpty else {
            return try await next.respond(to: request)
        }
        let baseLower = base.lowercased()
        guard host.hasSuffix("." + baseLower), host.count > baseLower.count + 1 else {
            return try await next.respond(to: request)
        }
        let prefix = String(host.dropLast(baseLower.count + 1))
        guard !prefix.isEmpty,
              let project = try await Project.query(on: request.db).filter(\.$subdomain == prefix).first() else {
            return try await next.respond(to: request)
        }
        request.storage[ResolvedHostProjectKey.self] = project
        return try await next.respond(to: request)
    }
}
