import Fluent
import Vapor

final class McpOAuthAccessToken: Model, Content {
    static let schema = "mcp_oauth_access_tokens"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "token_hash")
    var tokenHash: String

    @Parent(key: "project_id")
    var project: Project

    @Parent(key: "mcp_oauth_client_id")
    var client: McpOAuthClient

    @OptionalField(key: "account_id")
    var accountId: UUID?

    @Field(key: "subject_type")
    var subjectType: String

    @Field(key: "scope")
    var scope: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @OptionalField(key: "revoked_at")
    var revokedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        tokenHash: String,
        projectId: UUID,
        clientId: UUID,
        accountId: UUID?,
        subjectType: String,
        scope: String,
        expiresAt: Date
    ) {
        self.id = id
        self.tokenHash = tokenHash
        self.$project.id = projectId
        self.$client.id = clientId
        self.accountId = accountId
        self.subjectType = subjectType
        self.scope = scope
        self.expiresAt = expiresAt
    }
}

extension McpOAuthAccessToken: @unchecked Sendable {}
