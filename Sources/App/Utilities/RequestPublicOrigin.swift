import Vapor

enum RequestPublicOrigin {
    /// Best-effort public origin for the request (`X-Forwarded-Proto` first, then URL scheme).
    static func origin(for req: Request) -> String? {
        let scheme = forwardedProto(for: req) ?? req.url.scheme ?? "http"
        guard let host = req.headers.first(name: .host) else { return nil }
        return "\(scheme)://\(host)"
    }

    private static func forwardedProto(for req: Request) -> String? {
        guard let raw = req.headers.first(name: "X-Forwarded-Proto") else { return nil }
        let p = raw.split(separator: ",").first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p, !p.isEmpty else { return nil }
        return p
    }
}
