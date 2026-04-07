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
enum DatabaseBootstrapError: Error, CustomStringConvertible, LocalizedError {
    /// `APP_ENV` is `dev` or `prod` but neither URL nor all discrete Postgres fields are set.
    case missingRemotePostgresConfiguration

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
        }
    }

    var errorDescription: String? { description }
}

enum DatabaseBootstrap {
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
