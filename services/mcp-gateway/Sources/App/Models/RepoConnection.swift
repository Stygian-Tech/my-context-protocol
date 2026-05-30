import Fluent
import Vapor

final class RepoConnection: Model, Content {
    static let schema = "repo_connections"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "project_id")
    var project: Project

    @Field(key: "provider")
    var provider: String

    @Field(key: "repo_owner")
    var repoOwner: String

    @Field(key: "repo_name")
    var repoName: String

    @Field(key: "default_branch")
    var defaultBranch: String

    @Field(key: "auth_type")
    var authType: String

    @OptionalField(key: "token_ref")
    var tokenRef: String?

    @OptionalField(key: "webhook_id")
    var webhookId: String?

    @OptionalField(key: "webhook_secret")
    var webhookSecret: String?

    /// GitHub App installation id when Pro webhooks use installation access tokens.
    @OptionalField(key: "github_installation_id")
    var githubInstallationId: Int64?

    @OptionalField(key: "token_encrypted")
    var tokenEncrypted: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        projectId: UUID,
        provider: String,
        repoOwner: String,
        repoName: String,
        defaultBranch: String = "main",
        authType: String = "pat",
        tokenRef: String? = nil,
        webhookId: String? = nil,
        webhookSecret: String? = nil,
        githubInstallationId: Int64? = nil,
        tokenEncrypted: String? = nil
    ) {
        self.id = id
        self.$project.id = projectId
        self.provider = provider
        self.repoOwner = repoOwner
        self.repoName = repoName
        self.defaultBranch = defaultBranch
        self.authType = authType
        self.tokenRef = tokenRef
        self.webhookId = webhookId
        self.webhookSecret = webhookSecret
        self.githubInstallationId = githubInstallationId
        self.tokenEncrypted = tokenEncrypted
    }
}

extension RepoConnection: @unchecked Sendable {}
