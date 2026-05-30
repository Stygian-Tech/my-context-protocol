import Fluent
import Vapor

final class McpOAuthPendingAuthorization: Model {
    static let schema = "mcp_oauth_pending_authorizations"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "project_id")
    var project: Project

    @Parent(key: "mcp_oauth_client_id")
    var client: McpOAuthClient

    @Field(key: "redirect_uri")
    var redirectUri: String

    @Field(key: "state")
    var state: String

    @Field(key: "scope")
    var scope: String

    @Field(key: "code_challenge")
    var codeChallenge: String

    @Field(key: "code_challenge_method")
    var codeChallengeMethod: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        projectId: UUID,
        clientId: UUID,
        redirectUri: String,
        state: String,
        scope: String,
        codeChallenge: String,
        codeChallengeMethod: String,
        expiresAt: Date
    ) {
        self.id = id
        self.$project.id = projectId
        self.$client.id = clientId
        self.redirectUri = redirectUri
        self.state = state
        self.scope = scope
        self.codeChallenge = codeChallenge
        self.codeChallengeMethod = codeChallengeMethod
        self.expiresAt = expiresAt
    }
}

extension McpOAuthPendingAuthorization: @unchecked Sendable {}
