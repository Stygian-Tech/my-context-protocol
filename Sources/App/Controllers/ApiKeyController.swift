import Crypto
import Fluent
import Foundation
import Vapor

struct ApiKeyController {
    static func create(req: Request) async throws -> Response {
        guard let account = req.storage[AccountKey.self], let account = account else {
            return Response(status: .unauthorized, body: .init(string: "{\"error\":\"Not authenticated\"}"))
        }

        let projectSlug = Environment.get("PROJECT_SLUG") ?? "default"
        let project = try await Project.query(on: req.db)
            .filter(\.$slug == projectSlug)
            .filter(\.$account.$id == account.id!)
            .first()

        guard let project = project else {
            return Response(status: .notFound, body: .init(string: "{\"error\":\"Project not found\"}"))
        }

        let rawKey = "mcp_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let hash = SHA256.hash(data: Data(rawKey.utf8))
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        let prefix = String(rawKey.prefix(12))

        let apiKey = ApiKey(
            projectId: project.id!,
            keyPrefix: prefix,
            keyHash: hashString,
            status: "active"
        )
        try await apiKey.save(on: req.db)

        struct CreateResponse: Content {
            let key: String
            let prefix: String
            let message: String
        }
        let response = CreateResponse(
            key: rawKey,
            prefix: prefix,
            message: "Store this key securely. It will not be shown again."
        )
        return try await response.encodeResponse(for: req)
    }
}
