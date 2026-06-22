import Foundation
import NIOSSL
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
    /// `APP_ENV` is `prod` but certificate verification has been explicitly disabled.
    case insecurePostgresTLSInProduction
    /// A configured Postgres CA trust root could not be loaded.
    case invalidPostgresTLSRoot(reason: String)

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
        case .insecurePostgresTLSInProduction:
            """
            DATABASE_INSECURE_TLS is not allowed when APP_ENV=prod.

            Production database connections must use TLS with certificate verification enabled.
            Fix the production CA trust chain or use a verified managed-Postgres connection string instead of disabling certificate verification.
            """
        case .invalidPostgresTLSRoot(let reason):
            """
            Postgres TLS root certificate configuration is invalid: \(reason)

            If your managed Postgres provider uses a CA outside the container trust store, set DATABASE_SSLROOTCERT to a PEM file path, DATABASE_SSLROOTCERT_PEM to the PEM contents, or DATABASE_SSLROOTCERT_BASE64 to a base64-encoded PEM bundle.
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

    /// Rejects explicit TLS verification bypass in production.
    static func assertInsecurePostgresTLSAllowed(
        _ enabled: Bool,
        deployKind: DeployAppEnv = AppEnvironment.deployKind()
    ) throws {
        guard enabled, deployKind == .prod else { return }
        throw DatabaseBootstrapError.insecurePostgresTLSInProduction
    }

    /// Builds the verified TLS context used for production Postgres connections.
    ///
    /// NIOSSL uses the container's system trust store by default. Supabase and other managed Postgres
    /// providers can additionally require a provider CA bundle, so allow deployment to add one without
    /// disabling chain or hostname verification.
    static func verifiedPostgresSSLContext(connectionURL: String? = nil) throws -> NIOSSLContext {
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = .fullVerification

        let additionalRoots = try postgresAdditionalTrustRoots(connectionURL: connectionURL)
        if !additionalRoots.isEmpty {
            tlsConfig.additionalTrustRoots = additionalRoots
        }

        do {
            return try NIOSSLContext(configuration: tlsConfig)
        } catch {
            throw DatabaseBootstrapError.invalidPostgresTLSRoot(reason: "configured trust roots could not be loaded by NIOSSL")
        }
    }

    static func postgresAdditionalTrustRoots(connectionURL: String? = nil) throws -> [NIOSSLAdditionalTrustRoots] {
        var roots: [NIOSSLAdditionalTrustRoots] = []

        if let file = configuredPostgresSSLRootCertFile(connectionURL: connectionURL) {
            roots.append(.file(file))
        }
        if let pem = configuredPostgresSSLRootCertPEM() {
            roots.append(.certificates(try certificates(fromPEM: pem, source: "DATABASE_SSLROOTCERT_PEM")))
        }
        if let base64 = configuredPostgresSSLRootCertBase64() {
            roots.append(.certificates(try certificates(fromBase64PEM: base64, source: "DATABASE_SSLROOTCERT_BASE64")))
        }

        return roots
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

    private static func configuredPostgresSSLRootCertFile(connectionURL: String?) -> String? {
        for key in ["DATABASE_SSLROOTCERT", "DATABASE_SSL_ROOT_CERT_FILE", "DATABASE_TLS_CA_CERT_FILE"] {
            if let value = nonEmptyEnv(key) {
                return value
            }
        }

        guard let connectionURL,
              let components = URLComponents(string: connectionURL),
              let queryItems = components.queryItems
        else {
            return nil
        }
        return queryItems
            .last { $0.name.lowercased() == "sslrootcert" }
            .flatMap { normalizedNonEmpty($0.value) }
    }

    private static func configuredPostgresSSLRootCertPEM() -> String? {
        for key in ["DATABASE_SSLROOTCERT_PEM", "DATABASE_SSL_ROOT_CERT_PEM", "DATABASE_TLS_CA_CERT_PEM"] {
            if let value = nonEmptyEnv(key) {
                return value
            }
        }
        return nil
    }

    private static func configuredPostgresSSLRootCertBase64() -> String? {
        for key in ["DATABASE_SSLROOTCERT_BASE64", "DATABASE_SSL_ROOT_CERT_BASE64", "DATABASE_TLS_CA_CERT_BASE64"] {
            if let value = nonEmptyEnv(key) {
                return value
            }
        }
        return nil
    }

    private static func nonEmptyEnv(_ key: String) -> String? {
        normalizedNonEmpty(Environment.get(key))
    }

    private static func normalizedNonEmpty(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func certificates(fromPEM raw: String, source: String) throws -> [NIOSSLCertificate] {
        let pem = raw.replacingOccurrences(of: "\\n", with: "\n")
        do {
            let certs = try NIOSSLCertificate.fromPEMBytes(Array(pem.utf8))
            guard !certs.isEmpty else {
                throw DatabaseBootstrapError.invalidPostgresTLSRoot(reason: "\(source) did not contain any PEM certificates")
            }
            return certs
        } catch let error as DatabaseBootstrapError {
            throw error
        } catch {
            throw DatabaseBootstrapError.invalidPostgresTLSRoot(reason: "\(source) could not be parsed as PEM")
        }
    }

    private static func certificates(fromBase64PEM raw: String, source: String) throws -> [NIOSSLCertificate] {
        let compact = raw.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: String(compact)) else {
            throw DatabaseBootstrapError.invalidPostgresTLSRoot(reason: "\(source) is not valid base64")
        }
        guard let pem = String(data: data, encoding: .utf8) else {
            throw DatabaseBootstrapError.invalidPostgresTLSRoot(reason: "\(source) does not decode to UTF-8 PEM")
        }
        return try certificates(fromPEM: pem, source: source)
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
