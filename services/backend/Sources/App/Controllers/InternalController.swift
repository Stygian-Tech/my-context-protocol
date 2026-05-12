import Vapor

/// Endpoints called by internal infrastructure — not exposed to end users.
/// Currently used by Caddy's `on_demand_tls` ask hook to gate TLS certificate issuance.
struct InternalController {
    /// GET /internal/custom-domain/verify-for-tls?domain=mcp.example.com
    ///
    /// Returns 200 if Caddy should provision a TLS certificate for `domain`, 422 otherwise.
    /// Two classes of domain are allowed:
    ///   1. Any subdomain of `SAAS_MCP_BASE_DOMAIN` (e.g. `abc123.mcp.example.dev`)
    ///   2. A verified custom domain stored in the `projects` table
    ///
    /// Caddy calls this from localhost before completing a TLS handshake, so no auth is required.
    /// The endpoint returns no sensitive data — only a status code.
    static func verifyForTls(req: Request) async throws -> Response {
        guard let domain = req.query[String.self, at: "domain"],
              !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Response(status: .unprocessableEntity)
        }
        let host = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Allow any subdomain of the MCP base domain.
        if let rawBase = Environment.get("SAAS_MCP_BASE_DOMAIN")?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !rawBase.isEmpty {
            if host.hasSuffix("." + rawBase) {
                return Response(status: .ok)
            }
        }

        // Allow verified custom domains.
        let project = try await Project.query(on: req.db)
            .filter(\.$customDomain == host)
            .first()
        if let project, project.customDomainVerifiedAt != nil {
            return Response(status: .ok)
        }

        req.logger.warning("verify-for-tls rejected domain=\(host)")
        return Response(status: .unprocessableEntity)
    }
}
