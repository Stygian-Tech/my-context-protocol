import Crypto
import Fluent
import Vapor

struct ApiKeyMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let key: String?
        if let authHeader = request.headers.bearerAuthorization {
            key = authHeader.token
        } else if let apiKey = request.headers.first(name: "X-API-Key") {
            key = apiKey
        } else {
            request.logger.devTrace("api_key_auth missing")
            return Response(status: .unauthorized, body: .init(string: "Missing API key"))
        }

        guard let key = key, !key.isEmpty else {
            request.logger.devTrace("api_key_auth empty")
            return Response(status: .unauthorized, body: .init(string: "Invalid API key"))
        }

        let hash = SHA256.hash(data: Data(key.utf8))
        let hashString = hash.map { String(format: "%02x", $0) }.joined()

        let apiKey = try await ApiKey.query(on: request.db)
            .filter(\.$keyHash == hashString)
            .filter(\.$status == "active")
            .with(\.$project)
            .first()

        guard let apiKey = apiKey else {
            request.logger.devTrace("api_key_auth no_matching_active_key")
            return Response(status: .unauthorized, body: .init(string: "Invalid API key"))
        }

        if let hostProject = request.storage[ResolvedHostProjectKey.self],
           let hostPid = hostProject.id {
            guard apiKey.$project.id == hostPid else {
                request.logger.devTrace("api_key_auth host_mismatch tenantProject=\(hostPid) keyProject=\(apiKey.$project.id)")
                return Response(status: .forbidden, body: .init(string: "API key does not match host"))
            }
        }

        apiKey.lastUsedAt = Date()
        try await apiKey.save(on: request.db)

        request.storage[McpApiKeyRecordKey.self] = apiKey
        request.storage[ProjectKey.self] = apiKey.project
        let pid = apiKey.project.id?.uuidString ?? "nil"
        let kid = apiKey.id?.uuidString ?? "nil"
        request.logger.devTrace("api_key_auth ok keyId=\(kid) projectId=\(pid)")
        return try await next.respond(to: request)
    }
}

struct ProjectKey: StorageKey {
    typealias Value = Project
}

/// Active `ApiKey` model for MCP subscription bookkeeping (same lifetime as `ProjectKey`).
struct McpApiKeyRecordKey: StorageKey {
    typealias Value = ApiKey
}
