import Fluent
import Vapor

final class McpOAuthAuthorizationCode: Model {
    static let schema = "mcp_oauth_authorization_codes"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "code_hash")
    var codeHash: String

    @Parent(key: "project_id")
    var project: Project

    @Parent(key: "mcp_oauth_client_id")
    var client: McpOAuthClient

    @Parent(key: "account_id")
    var account: Account

    @Field(key: "redirect_uri")
    var redirectUri: String

    @Field(key: "scope")
    var scope: String

    @Field(key: "code_challenge")
    var codeChallenge: String

    @Field(key: "code_challenge_method")
    var codeChallengeMethod: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @OptionalField(key: "consumed_at")
    var consumedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        codeHash: String,
        projectId: UUID,
        clientId: UUID,
        accountId: UUID,
        redirectUri: String,
        scope: String,
        codeChallenge: String,
        codeChallengeMethod: String,
        expiresAt: Date
    ) {
        self.id = id
        self.codeHash = codeHash
        self.$project.id = projectId
        self.$client.id = clientId
        self.$account.id = accountId
        self.redirectUri = redirectUri
        self.scope = scope
        self.codeChallenge = codeChallenge
        self.codeChallengeMethod = codeChallengeMethod
        self.expiresAt = expiresAt
    }
}

extension McpOAuthAuthorizationCode: @unchecked Sendable {}
