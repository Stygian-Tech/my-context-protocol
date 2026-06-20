import Vapor

enum RequestPublicOrigin {
    /// Hostname used to resolve the tenant project (lowercase, no port). Prefer `X-Forwarded-Host` when
    /// `MCP_TRUST_X_FORWARDED_HOST` is enabled so verified custom domains work behind TLS-terminating proxies.
    static func routingHostname(for req: Request) -> String? {
        guard let hostFull = publicHostField(for: req) else { return nil }
        let host = String(canonicalHostPort(hostFull).split(separator: ":").first ?? Substring(hostFull)).lowercased()
        return host.isEmpty ? nil : host
    }

    /// Best-effort public origin for the request (`X-Forwarded-Proto`, optional `X-Forwarded-Host` when trusted).
    static func origin(for req: Request) -> String? {
        let scheme = forwardedProto(for: req) ?? req.url.scheme ?? "http"
        guard let hostRaw = publicHostField(for: req)?.trimmingCharacters(in: .whitespacesAndNewlines), !hostRaw.isEmpty else {
            return nil
        }
        let hostLower = canonicalHostPort(hostRaw)
        let displayHost = stripDefaultHttpPorts(from: hostLower, scheme: scheme)
        return "\(scheme)://\(displayHost)"
    }

    private static func publicHostField(for req: Request) -> String? {
        if AppEnvironment.mcpTrustXForwardedHost,
           let raw = req.headers.first(name: "X-Forwarded-Host") {
            let first = raw.split(separator: ",").first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let first, !first.isEmpty {
                return first
            }
        }
        return req.headers.first(name: .host)
    }

    private static func canonicalHostPort(_ raw: String) -> String {
        let hostPort = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !hostPort.contains("[") else { return hostPort }
        guard let colonIdx = hostPort.lastIndex(of: ":") else {
            return stripTrailingDots(hostPort)
        }
        let hostPart = stripTrailingDots(String(hostPort[..<colonIdx]))
        let portPart = String(hostPort[hostPort.index(after: colonIdx)...])
        return hostPart.isEmpty ? hostPort : "\(hostPart):\(portPart)"
    }

    private static func stripTrailingDots(_ raw: String) -> String {
        var s = raw
        while s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private static func forwardedProto(for req: Request) -> String? {
        guard let raw = req.headers.first(name: "X-Forwarded-Proto") else { return nil }
        let p = raw.split(separator: ",").first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p, !p.isEmpty else { return nil }
        return p
    }

    /// Drops `:443` / `:80` from host[:port] for canonical issuer URLs (not for bracketed IPv6).
    private static func stripDefaultHttpPorts(from hostPort: String, scheme: String) -> String {
        guard !hostPort.contains("[") else { return hostPort }
        guard let colonIdx = hostPort.lastIndex(of: ":") else { return hostPort }
        let hostPart = String(hostPort[..<colonIdx])
        let portStr = String(hostPort[hostPort.index(after: colonIdx)...])
        guard let p = Int(portStr) else { return hostPort }
        if scheme == "https", p == 443 { return hostPart }
        if scheme == "http", p == 80 { return hostPart }
        return hostPort
    }
}
