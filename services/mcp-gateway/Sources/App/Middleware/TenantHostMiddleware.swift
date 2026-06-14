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

        switch try await Self.resolveProject(for: host, request: request) {
        case .resolved(let project, let message):
            if project.suspendedAt != nil {
                return Response(status: .paymentRequired, body: .init(string: "This project is suspended. The account owner must select an active project or upgrade to Pro."))
            }
            request.storage[ResolvedHostProjectKey.self] = project
            request.logger.devTrace(message)
        case .unresolved(let message):
            request.logger.devTrace(message)
        }
        return try await next.respond(to: request)
    }

    enum Resolution {
        case resolved(Project, String)
        case unresolved(String)
    }

    static func resolveProject(for host: String, request: Request) async throws -> Resolution {
        if let byCustom = try await Project.query(on: request.db).filter(\.$customDomain == host).first(),
           byCustom.customDomainVerifiedAt != nil {
            return .resolved(
                byCustom,
                "tenant_host resolved=verified_custom_domain host=\(host) projectId=\(byCustom.id?.uuidString ?? "nil")"
            )
        }
        guard let base = Environment.get("SAAS_MCP_BASE_DOMAIN"), !base.isEmpty else {
            return .unresolved("tenant_host no_saas_base host=\(host) path=\(request.url.path)")
        }
        let baseLower = base.lowercased()
        guard host.hasSuffix("." + baseLower), host.count > baseLower.count + 1 else {
            return .unresolved("tenant_host not_subdomain_of base=\(baseLower) host=\(host)")
        }
        let prefix = String(host.dropLast(baseLower.count + 1))
        guard !prefix.isEmpty,
              let project = try await Project.query(on: request.db).filter(\.$subdomain == prefix).first() else {
            return .unresolved("tenant_host subdomain_unresolved prefix=\(prefix)")
        }
        return .resolved(project, "tenant_host resolved=subdomain prefix=\(prefix) projectId=\(project.id?.uuidString ?? "nil")")
    }
}
