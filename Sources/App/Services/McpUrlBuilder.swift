import Foundation
import Vapor

/// Builds the public MCP HTTP endpoint URL (`{scheme}://{host}{path}`) from env + project.
enum McpUrlBuilder {
    /// Full URL for `POST /mcp` for this project (verified custom domain, else `{subdomain}.{SAAS_MCP_BASE_DOMAIN}`).
    static func publicMcpUrl(for project: Project) -> String? {
        if let host = customDomainHost(project) {
            return build(host: host)
        }
        guard let sub = project.subdomain?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty,
              let baseRaw = Environment.get("SAAS_MCP_BASE_DOMAIN"),
              !baseRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let base = normalizeBaseDomain(baseRaw)
        return build(host: "\(sub).\(base)")
    }

    private static func customDomainHost(_ project: Project) -> String? {
        guard project.customDomainVerifiedAt != nil,
              let d = project.customDomain?.trimmingCharacters(in: .whitespacesAndNewlines),
              !d.isEmpty else { return nil }
        return d.lowercased()
    }

    private static func normalizeBaseDomain(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("https://") { s = String(s.dropFirst(8)) }
        else if s.hasPrefix("http://") { s = String(s.dropFirst(7)) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private static func normalizedScheme() -> String {
        let raw = Environment.get("SAAS_MCP_URL_SCHEME")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "https"
        if raw.isEmpty { return "https" }
        var s = raw.lowercased()
        if s.hasSuffix("://") { s = String(s.dropLast(3)) }
        if s.hasSuffix(":") { s.removeLast() }
        return s.isEmpty ? "https" : s
    }

    private static func normalizedPath() -> String {
        let raw = Environment.get("SAAS_MCP_PATH")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "/mcp"
        if raw.isEmpty { return "/mcp" }
        return raw.hasPrefix("/") ? raw : "/" + raw
    }

    private static func build(host: String) -> String {
        "\(normalizedScheme())://\(host)\(normalizedPath())"
    }
}
