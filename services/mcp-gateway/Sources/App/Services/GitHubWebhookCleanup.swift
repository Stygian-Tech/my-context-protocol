import Fluent
import Vapor

enum GitHubWebhookCleanup {
    /// Deletes GitHub repo webhooks we created and clears local webhook fields (e.g. after Pro downgrade).
    static func removeAllWebhooks(
        account: Account,
        db: Database,
        client: Client,
        logger: Logger
    ) async throws {
        guard let encrypted = account.githubTokenEncrypted,
              let token = try? TokenEncryption.decrypt(encrypted), !token.isEmpty else {
            return
        }
        let projects = try await account.$projects.get(on: db)
        for project in projects {
            let connections = try await project.$repoConnections.get(on: db)
            for conn in connections {
                guard let wid = conn.webhookId, !wid.isEmpty else { continue }
                let deleteToken: String
                if let iid = conn.githubInstallationId {
                    do {
                        deleteToken = try await GitHubAppInstallationTokenService.createInstallationToken(
                            installationId: iid,
                            client: client,
                            logger: logger,
                            db: db
                        )
                    } catch {
                        logger.warning("GitHub App installation token failed during webhook cleanup; skipping hook delete for \(conn.repoOwner)/\(conn.repoName)")
                        continue
                    }
                } else {
                    deleteToken = token
                }
                try? await GitHubWebhookService.deleteWebhook(
                    owner: conn.repoOwner,
                    repo: conn.repoName,
                    webhookId: wid,
                    token: deleteToken,
                    client: client
                )
                conn.webhookId = nil
                conn.webhookSecret = nil
                try await conn.save(on: db)
            }
        }
    }
}
