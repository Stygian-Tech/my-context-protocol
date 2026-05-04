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

        guard let signature = req.headers.first(name: "X-Hub-Signature-256") else {
            return Response(status: .unauthorized, body: .init(string: "Missing signature"))
        }
        guard GitHubWebhookHMAC.isValid(signatureHeader: signature, body: bodyData, secret: secret) else {
            return Response(status: .unauthorized, body: .init(string: "Invalid signature"))
        }

        let event = req.headers.first(name: "X-GitHub-Event") ?? ""

        if event == "installation" {
            struct InstallationEvent: Decodable {
                let action: String?
                let installation: Inst?
                struct Inst: Decodable { let id: Int64? }
            }
            guard let payload = try? JSONDecoder().decode(InstallationEvent.self, from: bodyData),
                  let action = payload.action,
                  let iid = payload.installation?.id else {
                return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
            }
            // Uninstall, suspend, or installer removing the integration — tokens stop working; clear local ids so connect-repo can require reinstall.
            if action == "deleted" || action == "suspend" {
                try await GitHubAppInstallationCleanup.clearReferences(installationId: iid, on: req.db, logger: req.logger)
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
            guard (try await Account.query(on: req.db).filter(\.$githubId == ghAccountId).first()) != nil else {
                return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
            }
            try await GitHubAppInstallationCleanup.clearAllForGitHubUser(
                githubUserId: ghAccountId,
                on: req.db,
                logger: req.logger
            )
            return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
        }

        return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
    }
}
