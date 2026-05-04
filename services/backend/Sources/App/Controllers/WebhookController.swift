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
            /// GitHub repo default branch (same commit as `HEAD` on the default branch).
            let default_branch: String?

            enum CodingKeys: String, CodingKey {
                case full_name
                case default_branch
            }
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

        guard let secret = connection.webhookSecret, !secret.isEmpty else {
            req.logger.warning("GitHub webhook rejected: missing webhook secret for \(owner)/\(repo)")
            return Response(status: .unauthorized, body: .init(string: "Webhook secret not configured for this repository"))
        }
        guard let signature = req.headers.first(name: "X-Hub-Signature-256") else {
            return Response(status: .badRequest, body: .init(string: "Missing signature"))
        }
        guard GitHubWebhookHMAC.isValid(signatureHeader: signature, body: bodyData, secret: secret) else {
            return Response(status: .unauthorized, body: .init(string: "Invalid signature"))
        }

        /// Auto-sync only when the push updates the repository default branch (GitHub `default_branch` / HEAD).
        guard let ref = payload.ref, ref.hasPrefix("refs/heads/") else {
            req.logger.debug(
                "GitHub webhook ignored for \(owner)/\(repo): ref=\(payload.ref ?? "nil") (not a branch push)"
            )
            return Response(status: .ok, body: .init(string: "{\"ok\":true,\"skipped\":\"not_branch\"}"))
        }

        let fromPayload = payload.repository?.default_branch?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fromConnection = connection.defaultBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let headBranch = fromPayload.isEmpty ? fromConnection : fromPayload

        guard !headBranch.isEmpty else {
            req.logger.warning(
                "GitHub webhook cannot resolve default branch for \(owner)/\(repo); skipping sync"
            )
            return Response(status: .ok, body: .init(string: "{\"ok\":true,\"skipped\":\"no_default_branch\"}"))
        }

        let expectedRef = "refs/heads/\(headBranch)"
        guard ref == expectedRef else {
            req.logger.debug(
                "GitHub webhook ignored for \(owner)/\(repo): ref=\(ref) (expected \(expectedRef) for default branch)"
            )
            return Response(status: .ok, body: .init(string: "{\"ok\":true,\"skipped\":\"not_default_branch\"}"))
        }

        if !fromPayload.isEmpty, connection.defaultBranch != fromPayload {
            connection.defaultBranch = fromPayload
            try await connection.save(on: req.db)
        }

        let project = connection.project

        let pipeline = SyncPipeline(db: req.db, app: req.application)
        try await pipeline.run(projectId: project.id!)

        return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
    }
}
