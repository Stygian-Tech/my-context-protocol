import Fluent
import Vapor

/// Clears local state when GitHub removes or suspends a GitHub App installation, or when the API reports the installation no longer exists.
enum GitHubAppInstallationCleanup {
    /// Drops `github_installation_id` and webhook fields on every `repo_connection`, and `github_app_installation_id` on every `account`, that reference this GitHub installation id.
    static func clearReferences(installationId: Int64, on db: Database, logger: Logger) async throws {
        let conns = try await RepoConnection.query(on: db).filter(\.$githubInstallationId == installationId).all()
        for conn in conns {
            conn.githubInstallationId = nil
            conn.webhookId = nil
            conn.webhookSecret = nil
            try await conn.save(on: db)
        }
        let accounts = try await Account.query(on: db).filter(\.$githubAppInstallationId == installationId).all()
        for acct in accounts {
            acct.githubAppInstallationId = nil
            try await acct.save(on: db)
        }
        if !conns.isEmpty || !accounts.isEmpty {
            logger.notice("GitHub App installation \(installationId) cleared from \(conns.count) repo connection(s) and \(accounts.count) account(s)")
        }
    }

    /// User revoked GitHub App authorization (or similar): clear installation + hooks on all of their projects.
    static func clearAllForGitHubUser(githubUserId: Int64, on db: Database, logger: Logger) async throws {
        guard let acct = try await Account.query(on: db).filter(\.$githubId == githubUserId).first(),
              let aid = acct.id else {
            return
        }
        acct.githubAppInstallationId = nil
        try await acct.save(on: db)
        let userProjects = try await Project.query(on: db).filter(\.$account.$id == aid).all()
        for project in userProjects {
            let conns = try await project.$repoConnections.get(on: db)
            for conn in conns {
                conn.githubInstallationId = nil
                conn.webhookId = nil
                conn.webhookSecret = nil
                try await conn.save(on: db)
            }
        }
        logger.notice("GitHub App references cleared for GitHub user id \(githubUserId) (authorization revoked)")
    }
}
