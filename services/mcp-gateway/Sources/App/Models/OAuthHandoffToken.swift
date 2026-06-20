import Fluent
import Vapor

final class OAuthHandoffToken: Model, @unchecked Sendable {
    static let schema = "oauth_handoff_tokens"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "token")
    var token: String

    @Field(key: "account_id")
    var accountId: UUID

    @Field(key: "expires_at")
    var expiresAt: Date

    @OptionalField(key: "created_at")
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, token: String, accountId: UUID, expiresAt: Date) {
        self.id = id
        self.token = token
        self.accountId = accountId
        self.expiresAt = expiresAt
    }
}
