import Foundation
import Logging
import Vapor

/// Dev-only verbose HTTP tracing and optional SQL query logging. Never enable in production (`APP_ENV=prod`).
enum DevLoggingConfig {
    /// When unset in non-production, verbose HTTP tracing is **on**. Set `DEV_LOG_HTTP=0` / `false` / `no` to disable.
    private static let verboseHttpKey = "DEV_LOG_HTTP"

    /// Per-RPC MCP handler traces (`Logger.mcpTrace`, `.debug`). When unset in non-production, **on**. Set `DEV_LOG_MCP=0` to disable.
    private static let mcpRpcTraceKey = "DEV_LOG_MCP"

    /// 1/true/yes: log SQL from Fluent drivers at `.debug` (requires `APP_ENV=local|dev`). Independent of HTTP tracing.
    private static let sqlKey = "DEV_LOG_SQL"

    static var verboseHttpEnabled: Bool {
        guard AppEnvironment.isNonProduction else { return false }
        guard let raw = Environment.get(verboseHttpKey) else {
            return true
        }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if v.isEmpty { return true }
        if v == "0" || v == "false" || v == "no" { return false }
        if v == "1" || v == "true" || v == "yes" { return true }
        return true
    }

    /// MCP JSON-RPC dispatch traces (each handler). Uses `.debug`; non-production defaults `LOG_LEVEL` to `.debug` when unset so these lines appear.
    static var mcpRpcTraceEnabled: Bool {
        guard AppEnvironment.isNonProduction else { return false }
        guard let raw = Environment.get(mcpRpcTraceKey) else {
            return true
        }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if v.isEmpty { return true }
        if v == "0" || v == "false" || v == "no" { return false }
        if v == "1" || v == "true" || v == "yes" { return true }
        return true
    }

    /// SQL log level for Fluent Postgres driver (non-optional in driver).
    static var postgresSqlLogLevel: Logger.Level {
        guard AppEnvironment.isNonProduction, envTruthy(sqlKey) else {
            return .critical
        }
        return .debug
    }

    /// SQL log level for Fluent SQLite driver (`nil` disables query logging at the driver).
    static var sqliteSqlLogLevel: Logger.Level? {
        guard AppEnvironment.isNonProduction, envTruthy(sqlKey) else {
            return nil
        }
        return .debug
    }

    static func envTruthy(_ key: String) -> Bool {
        guard let raw = Environment.get(key) else { return false }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == "1" || v == "true" || v == "yes"
    }
}

/// Header/query redaction for dev access logs.
enum DevLogRedaction {
    private static let sensitiveQueryKeyFragments: [String] = [
        "code", "state", "token", "secret", "key", "password", "session", "csrf",
        "access_token", "refresh_token", "id_token",
    ]

    private static let sensitiveHeaderNames: Set<String> = [
        "authorization", "cookie", "set-cookie", "x-api-key",
    ]

    static func redactedQueryString(_ query: String?) -> String {
        guard let query, !query.isEmpty else { return "-" }
        let pairs = query.split(separator: "&")
        let mapped = pairs.map { pair -> String in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = parts.first else { return String(pair) }
            let key = String(rawKey).removingPercentEncoding ?? String(rawKey)
            let keyLower = key.lowercased()
            if sensitiveQueryKeyFragments.contains(where: { keyLower.contains($0) }) {
                return "\(key)=[REDACTED]"
            }
            return String(pair)
        }
        return mapped.joined(separator: "&")
    }

    static func safeRequestHeaders(from headers: HTTPHeaders) -> String {
        var parts: [String] = []
        for (name, value) in headers {
            if sensitiveHeaderNames.contains(name.lowercased()) {
                parts.append("\(name):[REDACTED]")
                continue
            }
            parts.append("\(name):\(value)")
        }
        return parts.sorted().joined(separator: "; ")
    }

    static func safeResponseHeaders(from headers: HTTPHeaders) -> String {
        var parts: [String] = []
        for (name, value) in headers {
            if sensitiveHeaderNames.contains(name.lowercased()) {
                parts.append("\(name):[REDACTED]")
                continue
            }
            parts.append("\(name):\(value)")
        }
        return parts.sorted().joined(separator: "; ")
    }
}

extension Logger {
    /// Structured dev trace line when verbose HTTP tracing is enabled in non-production (default on; see `DEV_LOG_HTTP`).
    /// Uses `info` so traces show under the default process log level (`LOG_LEVEL=info`).
    func devTrace(_ message: String) {
        guard DevLoggingConfig.verboseHttpEnabled else { return }
        self.info("\(message)")
    }

    /// Finer MCP RPC tracing (handler steps). Emits at `.debug` when `DEV_LOG_MCP` is on (default in non-production).
    func mcpTrace(_ message: @autoclosure () -> String) {
        guard DevLoggingConfig.mcpRpcTraceEnabled else { return }
        self.debug("\(message())")
    }
}
