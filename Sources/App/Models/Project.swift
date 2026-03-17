import Fluent
import Vapor

final class Project: Model, Content {
    static let schema = "projects"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "account_id")
    var account: Account

    @Field(key: "name")
    var name: String

    @Field(key: "slug")
    var slug: String

    @OptionalField(key: "subdomain")
    var subdomain: String?

    @OptionalField(key: "active_release_id")
    var activeReleaseId: UUID?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Children(for: \.$project)
    var repoConnections: [RepoConnection]

    @Children(for: \.$project)
    var releases: [Release]

    @Children(for: \.$project)
    var apiKeys: [ApiKey]

    @Children(for: \.$project)
    var authConfigs: [AuthConfig]

    init() {}

    init(
        id: UUID? = nil,
        accountId: UUID,
        name: String,
        slug: String,
        subdomain: String? = nil,
        activeReleaseId: UUID? = nil
    ) {
        self.id = id
        self.$account.id = accountId
        self.name = name
        self.slug = slug
        self.subdomain = subdomain
        self.activeReleaseId = activeReleaseId
    }
}

extension Project: @unchecked Sendable {}
