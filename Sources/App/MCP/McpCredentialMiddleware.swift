import Crypto
import Fluent
import SQLKit
import Vapor

struct ProjectKey: StorageKey {
    typealias Value = Project
}

/// Active `ApiKey` model for MCP subscription bookkeeping (same lifetime as `ProjectKey`).
struct McpApiKeyRecordKey: StorageKey {
    typealias Value = ApiKey
}

enum McpCredentialKind: String, Sendable {
    case apiKey
    case oauthUser
    case oauthClientCredentials
}

struct McpCredentialKindKey: StorageKey {
    typealias Value = McpCredentialKind
}

struct McpOAuthAccessTokenRecordKey: StorageKey {
    typealias Value = McpOAuthAccessToken
}

/// Resolves MCP credentials: legacy API keys (`X-API-Key` or `Authorization: Bearer` API key) and OAuth access tokens (`Authorization: Bearer mcp_oat_…`).
struct McpCredentialMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        if let apiKeyHeader = request.headers.first(name: "X-API-Key"), !apiKeyHeader.isEmpty {
            return try await resolveApiKey(rawKey: apiKeyHeader, request: request, chainingTo: next)
        }
        if let bearer = request.headers.bearerAuthorization {
            return try await resolveBearer(token: bearer.token, request: request, chainingTo: next)
        }

        request.logger.devTrace("mcp_credential missing")
        if AppEnvironment.mcpOAuthEnabled, let origin = RequestPublicOrigin.origin(for: request) {
            let meta = "\(origin)/.well-known/oauth-protected-resource"
            var res = Response(status: .unauthorized, body: .init(string: "Unauthorized"))
            res.headers.replaceOrAdd(
                name: .wwwAuthenticate,
                value: "Bearer resource_metadata=\"\(meta)\""
            )
            return res
        }
        return Response(status: .unauthorized, body: .init(string: "Missing API key"))
    }

    private func resolveApiKey(rawKey: String, request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let hashString = Self.hashKey(rawKey)
        let apiKey = try await ApiKey.query(on: request.db)
            .filter(\.$keyHash == hashString)
            .filter(\.$status == "active")
            .with(\.$project)
            .first()

        guard let apiKey = apiKey else {
            request.logger.devTrace("mcp_credential api_key_invalid")
            return Self.unauthorizedResponse(request: request, message: "Invalid API key")
        }
        if let hostProject = request.storage[ResolvedHostProjectKey.self],
           let hostPid = hostProject.id {
            guard apiKey.$project.id == hostPid else {
                request.logger.devTrace("mcp_credential api_key_host_mismatch")
                return Response(status: .forbidden, body: .init(string: "API key does not match host"))
            }
        }
        Self.touchApiKeyLastUsed(apiKey: apiKey, request: request)
        request.storage[McpApiKeyRecordKey.self] = apiKey
        request.storage[ProjectKey.self] = apiKey.project
        request.storage[McpCredentialKindKey.self] = .apiKey
        request.storage[McpOAuthAccessTokenRecordKey.self] = nil
        return try await next.respond(to: request)
    }

    private func resolveBearer(token raw: String, request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Self.unauthorizedResponse(request: request, message: "Invalid bearer token")
        }

        let hashString = Self.hashKey(trimmed)
        if let apiKey = try await ApiKey.query(on: request.db)
            .filter(\.$keyHash == hashString)
            .filter(\.$status == "active")
            .with(\.$project)
            .first() {
            if let hostProject = request.storage[ResolvedHostProjectKey.self],
               let hostPid = hostProject.id {
                guard apiKey.$project.id == hostPid else {
                    request.logger.devTrace("mcp_credential bearer_api_key_host_mismatch")
                    return Response(status: .forbidden, body: .init(string: "API key does not match host"))
                }
            }
            Self.touchApiKeyLastUsed(apiKey: apiKey, request: request)
            request.storage[McpApiKeyRecordKey.self] = apiKey
            request.storage[ProjectKey.self] = apiKey.project
            request.storage[McpCredentialKindKey.self] = .apiKey
            request.storage[McpOAuthAccessTokenRecordKey.self] = nil
            return try await next.respond(to: request)
        }

        guard AppEnvironment.mcpOAuthEnabled else {
            request.logger.devTrace("mcp_credential oauth_disabled_bearer_miss")
            return Self.unauthorizedResponse(request: request, message: "Invalid API key")
        }

        guard let row = try await McpOAuthAccessToken.query(on: request.db)
            .filter(\.$tokenHash == hashString)
            .with(\.$project)
            .with(\.$client)
            .first(),
            row.revokedAt == nil,
            row.expiresAt > Date() else {
            request.logger.devTrace("mcp_credential oauth_token_invalid")
            return Self.unauthorizedResponse(request: request, message: "Invalid or expired token")
        }

        if let hostProject = request.storage[ResolvedHostProjectKey.self],
           let hostPid = hostProject.id {
            guard row.$project.id == hostPid else {
                request.logger.devTrace("mcp_credential oauth_host_mismatch")
                return Response(status: .forbidden, body: .init(string: "Token does not match host"))
            }
        }

        request.storage[McpApiKeyRecordKey.self] = nil
        request.storage[ProjectKey.self] = row.project
        request.storage[McpOAuthAccessTokenRecordKey.self] = row
        switch row.subjectType {
        case "service":
            request.storage[McpCredentialKindKey.self] = .oauthClientCredentials
        default:
            request.storage[McpCredentialKindKey.self] = .oauthUser
        }
        return try await next.respond(to: request)
    }

    private static func hashKey(_ raw: String) -> String {
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func touchApiKeyLastUsed(apiKey: ApiKey, request: Request) {
        if let kid = apiKey.id, let sql = request.application.db as? SQLDatabase {
            let now = Date()
            Task {
                try? await sql.update("api_keys")
                    .set(SQLColumn("last_used_at"), to: SQLBind(now))
                    .where(SQLColumn("id"), .equal, SQLBind(kid))
                    .run()
            }
        }
    }

    private static func unauthorizedResponse(request: Request, message: String) -> Response {
        if AppEnvironment.mcpOAuthEnabled, let origin = RequestPublicOrigin.origin(for: request) {
            let meta = "\(origin)/.well-known/oauth-protected-resource"
            var res = Response(status: .unauthorized, body: .init(string: message))
            res.headers.replaceOrAdd(
                name: .wwwAuthenticate,
                value: "Bearer resource_metadata=\"\(meta)\""
            )
            return res
        }
        return Response(status: .unauthorized, body: .init(string: message))
    }
}
