import Foundation
import NIOConcurrencyHelpers
import Vapor

/// Simple fixed-window rate limiter for MCP (per-process; pair with edge rate limiting at scale).
final class McpIpRateLimitMiddleware: AsyncMiddleware, @unchecked Sendable {
    private let buckets = NIOLockedValueBox<[String: (count: Int, reset: Date)]>([:])
    private let limit: Int
    private let windowSeconds: TimeInterval
    /// Cached at init time so the env lookup does not happen on every MCP request.
    private let trustXForwardedFor: Bool

    init(limit: Int, windowSeconds: TimeInterval) {
        self.limit = max(1, limit)
        self.windowSeconds = max(1, windowSeconds)
        let raw = Environment.get("TRUST_X_FORWARDED_FOR")?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        self.trustXForwardedFor = (raw == "1" || raw == "true" || raw == "yes")
    }

    convenience init() {
        let perMinute = Environment.get("MCP_RATE_LIMIT_PER_MINUTE").flatMap(Int.init) ?? 300
        self.init(limit: perMinute, windowSeconds: 60)
    }

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard AppEnvironment.rateLimitMcpEnabled else {
            return try await next.respond(to: request)
        }
        let key = clientKey(for: request)
        let now = Date()
        let allowed = buckets.withLockedValue { map in
            if map.count > 50_000 {
                map = [:]
            }
            if let state = map[key] {
                if now < state.reset {
                    if state.count >= limit {
                        return false
                    }
                    map[key] = (state.count + 1, state.reset)
                    return true
                }
            }
            map[key] = (1, now.addingTimeInterval(windowSeconds))
            return true
        }

        guard allowed else {
            let trace = request.storage[RequestTraceIDKey.self].map { " traceId=\($0)" } ?? ""
            request.logger.devTrace("mcp_rate_limit blocked\(trace) clientKey=\(key)")
            return Response(status: .tooManyRequests, body: .init(string: "Rate limited"))
        }
        return try await next.respond(to: request)
    }

    private func clientKey(for request: Request) -> String {
        if trustXForwardedFor,
           Self.isTrustedForwardingPeer(request.remoteAddress?.ipAddress),
           let xff = request.headers.first(name: "X-Forwarded-For"),
           let first = xff.split(separator: ",").first {
            return String(first).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let ip = request.remoteAddress?.ipAddress {
            return ip
        }
        return request.remoteAddress?.description ?? "unknown"
    }

    private static func isTrustedForwardingPeer(_ ip: String?) -> Bool {
        guard let ip = ip?.trimmingCharacters(in: .whitespacesAndNewlines), !ip.isEmpty else {
            return false
        }
        if ip == "::1" || ip == "127.0.0.1" || ip.hasPrefix("127.") {
            return true
        }
        if ip.hasPrefix("10.") || ip.hasPrefix("192.168.") {
            return true
        }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        if ip.hasPrefix("fc") || ip.hasPrefix("fd") || ip.hasPrefix("fe80:") {
            return true
        }
        return false
    }
}
