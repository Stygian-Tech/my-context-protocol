import Foundation
import Vapor

/// Discrete Postgres connection fields when `DATABASE_URL` / `SUPABASE_DB_URL` are unset.
struct PostgresDiscreteConnectionParams: Equatable, Sendable {
    var hostname: String
    var username: String
    var password: String
    var database: String
    var port: Int
}

/// Misconfiguration detected before opening a DB pool (avoids silent `localhost` + `vapor_*` in dev/prod).
enum DatabaseBootstrapError: Error, Equatable, CustomStringConvertible, LocalizedError {
    /// `APP_ENV` is `dev` or `prod` but neither URL nor all discrete Postgres fields are set.
    case missingRemotePostgresConfiguration
    /// `APP_ENV` is `dev` or `prod` but Postgres host resolves to loopback (common bad copy-paste into containers).
    case loopbackPostgresHostInDeployedAppEnv(host: String)

    var description: String {
        switch self {
        case .missingRemotePostgresConfiguration:
            """
            Database configuration incomplete for APP_ENV=dev or APP_ENV=prod.

            Set one of:
            - DATABASE_URL (preferred), or
            - SUPABASE_DB_URL, or
            - all of DATABASE_HOST, DATABASE_USERNAME, DATABASE_PASSWORD, DATABASE_NAME (optional DATABASE_PORT, default 5432).

            For local file SQLite instead, set USE_SQLITE=1.

            In containers, `localhost` refers to the container itself — use your managed Postgres hostname or a full connection URL.
            """
        case .loopbackPostgresHostInDeployedAppEnv(let host):
            """
            Postgres host `\(host)` is loopback, which is invalid for APP_ENV=dev or APP_ENV=prod in most Docker/Kubernetes deployments (nothing listens on 127.0.0.1 inside the API container).

            Point DATABASE_URL, SUPABASE_DB_URL, or DATABASE_HOST at your real database hostname (e.g. Supabase pooler).

            If you intentionally use loopback (rare), set DATABASE_ALLOW_LOOPBACK=1.
            """
        }
    }

    var errorDescription: String? { description }
}

enum DatabaseBootstrap {
    /// Host from `postgres://…` / `postgresql://…` for loopback checks. Returns `nil` if the string is not URL-parseable.
    static func hostnameForPostgresConnectionURL(_ string: String) -> String? {
        guard let url = URL(string: string), let host = url.host, !host.isEmpty else { return nil }
        return host
    }

    /// Rejects loopback Postgres targets when `APP_ENV` is `dev` or `prod`, unless `DATABASE_ALLOW_LOOPBACK` is truthy.
    static func assertPostgresConnectionURLHostAllowedIfResolvable(_ urlString: String) throws {
        guard let host = hostnameForPostgresConnectionURL(urlString) else { return }
        try assertPostgresHostAllowedForDeployedAppEnv(host)
    }

    static func assertPostgresHostAllowedForDeployedAppEnv(_ hostname: String) throws {
        switch AppEnvironment.deployKind() {
        case .local:
            return
        case .dev, .prod:
            break
        }
        guard !isTruthyEnv("DATABASE_ALLOW_LOOPBACK") else { return }
        guard isLoopbackPostgresHost(hostname) else { return }
        throw DatabaseBootstrapError.loopbackPostgresHostInDeployedAppEnv(host: hostname)
    }

    private static func isLoopbackPostgresHost(_ hostname: String) -> Bool {
        var h = hostname.lowercased()
        if h.hasPrefix("[") && h.hasSuffix("]") {
            h.removeFirst()
            h.removeLast()
        }
        if h == "localhost" || h == "::1" || h == "0:0:0:0:0:0:0:1" { return true }
        if h.hasPrefix("127.") { return true }
        return false
    }

    private static func isTruthyEnv(_ key: String) -> Bool {
        guard let raw = Environment.get(key) else { return false }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == "1" || v == "true" || v == "yes"
    }

    /// Builds discrete Postgres settings for the final `configure` branch (no URL, not SQLite, not testing fallback).
    ///
    /// - **local**: Missing fields fall back to `localhost` / `vapor_*` for bare-metal dev with a local Postgres.
    /// - **dev / prod**: All of host, username, password, database must be non-empty after trimming.
    static func postgresDiscreteParameters(for deployKind: DeployAppEnv) throws -> PostgresDiscreteConnectionParams {
        let rawHost = Environment.get("DATABASE_HOST")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawUser = Environment.get("DATABASE_USERNAME")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawPassword = Environment.get("DATABASE_PASSWORD")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawDatabase = Environment.get("DATABASE_NAME")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let port = Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432

        switch deployKind {
        case .local:
            return PostgresDiscreteConnectionParams(
                hostname: rawHost.isEmpty ? "localhost" : rawHost,
                username: rawUser.isEmpty ? "vapor_username" : rawUser,
                password: rawPassword.isEmpty ? "vapor_password" : rawPassword,
                database: rawDatabase.isEmpty ? "vapor_database" : rawDatabase,
                port: port
            )
        case .dev, .prod:
            guard !rawHost.isEmpty, !rawUser.isEmpty, !rawPassword.isEmpty, !rawDatabase.isEmpty else {
                throw DatabaseBootstrapError.missingRemotePostgresConfiguration
            }
            return PostgresDiscreteConnectionParams(
                hostname: rawHost,
                username: rawUser,
                password: rawPassword,
                database: rawDatabase,
                port: port
            )
        }
    }
}
