import Crypto
import Fluent
import Vapor

/// App-level GitHub webhooks (`installation`, `github_app_authorization`, etc.) using `GITHUB_APP_WEBHOOK_SECRET`.
enum GitHubAppWebhookController {
    static func handle(req: Request) async throws -> Response {
        guard let secret = Environment.get("GITHUB_APP_WEBHOOK_SECRET"), !secret.isEmpty else {
            throw Abort(.notFound)
        }

        guard let rawBody = req.body.data else {
            return Response(status: .badRequest, body: .init(string: "Missing body"))
        }
        let bodyData = Data(buffer: rawBody)

        if let signature = req.headers.first(name: "X-Hub-Signature-256") {
            let key = SymmetricKey(data: Data(secret.utf8))
            let mac = HMAC<SHA256>.authenticationCode(for: bodyData, using: key)
            let expected = "sha256=" + mac.map { String(format: "%02x", $0) }.joined()
            guard signature == expected else {
                return Response(status: .unauthorized, body: .init(string: "Invalid signature"))
            }
        } else {
            return Response(status: .unauthorized, body: .init(string: "Missing signature"))
        }

        let event = req.headers.first(name: "X-GitHub-Event") ?? ""

        if event == "installation" {
            struct InstallationEvent: Decodable {
                let action: String?
                let installation: Inst?
                struct Inst: Decodable { let id: Int64? }
            }
            guard let payload = try? JSONDecoder().decode(InstallationEvent.self, from: bodyData),
                  payload.action == "deleted",
                  let iid = payload.installation?.id else {
                return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
            }
            let conns = try await RepoConnection.query(on: req.db)
                .filter(\.$githubInstallationId == iid)
                .all()
            for conn in conns {
                conn.githubInstallationId = nil
                conn.webhookId = nil
                conn.webhookSecret = nil
                try await conn.save(on: req.db)
            }
            return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
        }

        if event == "github_app_authorization" {
            struct AuthEvent: Decodable {
                let action: String?
                struct Acct: Decodable { let id: Int64 }
                let account: Acct?
            }
            guard let payload = try? JSONDecoder().decode(AuthEvent.self, from: bodyData),
                  payload.action == "revoked",
                  let ghAccountId = payload.account?.id else {
                return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
            }
            guard let acct = try await Account.query(on: req.db)
                .filter(\.$githubId == ghAccountId)
                .first(),
                let aid = acct.id else {
                return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
            }
            let userProjects = try await Project.query(on: req.db)
                .filter(\.$account.$id == aid)
                .all()
            for project in userProjects {
                let conns = try await project.$repoConnections.get(on: req.db)
                for conn in conns {
                    conn.githubInstallationId = nil
                    conn.webhookId = nil
                    conn.webhookSecret = nil
                    try await conn.save(on: req.db)
                }
            }
            return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
        }

        return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
    }
}
