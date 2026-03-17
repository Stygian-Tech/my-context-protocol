import Fluent
import Vapor

final class Account: Model, Content {
    static let schema = "accounts"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "github_id")
    var githubId: Int64

    @Field(key: "login")
    var login: String

    @OptionalField(key: "avatar_url")
    var avatarUrl: String?

    @OptionalField(key: "email")
    var email: String?

    @OptionalField(key: "github_token_encrypted")
    var githubTokenEncrypted: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Children(for: \.$account)
    var projects: [Project]

    init() {}

    init(
        id: UUID? = nil,
        githubId: Int64,
        login: String,
        avatarUrl: String? = nil,
        email: String? = nil
    ) {
        self.id = id
        self.githubId = githubId
        self.login = login
        self.avatarUrl = avatarUrl
        self.email = email
    }
}

extension Account: @unchecked Sendable {}
