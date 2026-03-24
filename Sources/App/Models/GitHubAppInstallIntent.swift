import Fluent
import Vapor

/// Persists install context keyed by `id` (sent to GitHub as `state=`) so callbacks work without sticky sessions.
final class GitHubAppInstallIntent: Model, Content {
    static let schema = "github_app_install_intents"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "project_id")
    var project: Project

    @Parent(key: "account_id")
    var account: Account

    @OptionalField(key: "return_to")
    var returnTo: String?

    @OptionalField(key: "owner")
    var owner: String?

    @OptionalField(key: "repo")
    var repo: String?

    @Field(key: "expires_at")
    var expiresAt: Date

    init() {}

    init(
        id: UUID = UUID(),
        projectId: UUID,
        accountId: UUID,
        returnTo: String?,
        owner: String?,
        repo: String?,
        expiresAt: Date
    ) {
        self.id = id
        self.$project.id = projectId
        self.$account.id = accountId
        self.returnTo = returnTo
        self.owner = owner
        self.repo = repo
        self.expiresAt = expiresAt
    }
}

extension GitHubAppInstallIntent: @unchecked Sendable {}
