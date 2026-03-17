import Crypto
import CryptoKit
import Fluent
import Vapor

struct WebhookController {
    static func github(req: Request) async throws -> Response {
        struct GitHubPayload: Content {
            let ref: String?
            let repository: Repository?
        }
        struct Repository: Content {
            let full_name: String?
        }

        guard let rawBody = req.body.data else {
            return Response(status: .badRequest, body: .init(string: "Missing body"))
        }
        let bodyData = Data(buffer: rawBody)

        let payload: GitHubPayload
        do {
            payload = try JSONDecoder().decode(GitHubPayload.self, from: bodyData)
        } catch {
            return Response(status: .badRequest, body: .init(string: "Invalid payload"))
        }
        guard let repoName = payload.repository?.full_name else {
            return Response(status: .badRequest, body: .init(string: "Invalid payload"))
        }

        let parts = repoName.split(separator: "/")
        guard parts.count >= 2 else {
            return Response(status: .badRequest, body: .init(string: "Invalid repo name"))
        }
        let owner = String(parts[0])
        let repo = String(parts[1])

        let connection = try await RepoConnection.query(on: req.db)
            .filter(\.$repoOwner == owner)
            .filter(\.$repoName == repo)
            .with(\.$project)
            .first()

        guard let connection = connection else {
            return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
        }

        if let secret = connection.webhookSecret, !secret.isEmpty {
            guard let signature = req.headers.first(name: "X-Hub-Signature-256") else {
                return Response(status: .badRequest, body: .init(string: "Missing signature"))
            }
            let key = SymmetricKey(data: Data(secret.utf8))
            let mac = HMAC<SHA256>.authenticationCode(for: bodyData, using: key)
            let expected = "sha256=" + mac.map { String(format: "%02x", $0) }.joined()
            guard signature == expected else {
                return Response(status: .unauthorized, body: .init(string: "Invalid signature"))
            }
        }

        let project = connection.project

        let pipeline = SyncPipeline(db: req.db, app: req.application)
        try await pipeline.run(projectId: project.id!)

        return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
    }
}
