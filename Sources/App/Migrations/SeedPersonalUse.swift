import Fluent
import Vapor

struct SeedPersonalUse: AsyncMigration {
    func prepare(on database: Database) async throws {
        let email = Environment.get("ADMIN_EMAIL") ?? "admin@localhost"
        if try await Account.query(on: database).filter(\.$email == email).first() != nil {
            return
        }

        let password = Environment.get("ADMIN_PASSWORD") ?? "admin"
        let passwordHash = try Bcrypt.hash(password)

        let account = Account(email: email, passwordHash: passwordHash)
        try await account.save(on: database)

        let projectSlug = Environment.get("PROJECT_SLUG") ?? "my-skills"
        let project = Project(
            accountId: account.id!,
            name: "My Skills",
            slug: projectSlug,
            subdomain: nil
        )
        try await project.save(on: database)

        let repoParts = (Environment.get("GITHUB_REPO") ?? "owner/repo").split(separator: "/")
        let owner = String(repoParts.first ?? "owner")
        let repo = repoParts.count > 1 ? String(repoParts[1]) : "repo"
        let branch = Environment.get("GITHUB_BRANCH") ?? "main"

        let connection = RepoConnection(
            projectId: project.id!,
            provider: "github",
            repoOwner: owner,
            repoName: repo,
            defaultBranch: branch,
            authType: "pat"
        )
        try await connection.save(on: database)

        let authConfig = AuthConfig(projectId: project.id!, mode: "api_key")
        try await authConfig.save(on: database)
    }

    func revert(on database: Database) async throws {
        try await ApiKey.query(on: database).delete()
        try await AuthConfig.query(on: database).delete()
        try await RepoConnection.query(on: database).delete()
        try await Project.query(on: database).delete()
        try await Account.query(on: database).delete()
    }
}
