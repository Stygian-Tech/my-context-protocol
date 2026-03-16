import Crypto
import CryptoKit
import Fluent
import Vapor

struct WebhookController {
    static func github(req: Request) async throws -> Response {
        let secret = Environment.get("WEBHOOK_SECRET") ?? ""
        if !secret.isEmpty {
            guard let signature = req.headers.first(name: "X-Hub-Signature-256"),
                  let body = req.body.data else {
                return Response(status: .badRequest, body: .init(string: "Missing signature or body"))
            }
            let key = SymmetricKey(data: Data(secret.utf8))
            let bodyData = Data(buffer: body)
            let mac = HMAC<SHA256>.authenticationCode(for: bodyData, using: key)
            let expected = "sha256=" + mac.map { String(format: "%02x", $0) }.joined()
            guard signature == expected else {
                return Response(status: .unauthorized, body: .init(string: "Invalid signature"))
            }
        }

        struct GitHubPayload: Content {
            let ref: String?
            let repository: Repository?
        }
        struct Repository: Content {
            let full_name: String?
        }

        let payload = try req.content.decode(GitHubPayload.self)
        guard let repoName = payload.repository?.full_name else {
            return Response(status: .badRequest, body: .init(string: "Invalid payload"))
        }

        let parts = repoName.split(separator: "/")
        guard parts.count >= 2 else {
            return Response(status: .badRequest, body: .init(string: "Invalid repo name"))
        }

        let projectSlug = Environment.get("PROJECT_SLUG") ?? "default"
        let project = try await Project.query(on: req.db)
            .filter(\.$slug == projectSlug)
            .first()

        guard let project = project else {
            return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
        }

        let pipeline = SyncPipeline(db: req.db, app: req.application)
        try await pipeline.run(projectId: project.id!)

        return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
    }
}
