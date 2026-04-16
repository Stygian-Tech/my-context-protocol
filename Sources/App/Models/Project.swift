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

    @OptionalField(key: "custom_domain")
    var customDomain: String?

    @OptionalField(key: "custom_domain_verified_at")
    var customDomainVerifiedAt: Date?

    @OptionalField(key: "custom_domain_verification_token")
    var customDomainVerificationToken: String?

    @OptionalField(key: "active_release_id")
    var activeReleaseId: UUID?

    /// When set (non-empty after trim), the `mycontext_catalog` MCP tool returns this markdown instead of the auto-generated catalog.
    @OptionalField(key: "mcp_catalog_markdown_override")
    var mcpCatalogMarkdownOverride: String?

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
        customDomain: String? = nil,
        customDomainVerifiedAt: Date? = nil,
        customDomainVerificationToken: String? = nil,
        activeReleaseId: UUID? = nil,
        mcpCatalogMarkdownOverride: String? = nil
    ) {
        self.id = id
        self.$account.id = accountId
        self.name = name
        self.slug = slug
        self.subdomain = subdomain
        self.customDomain = customDomain
        self.customDomainVerifiedAt = customDomainVerifiedAt
        self.customDomainVerificationToken = customDomainVerificationToken
        self.activeReleaseId = activeReleaseId
        self.mcpCatalogMarkdownOverride = mcpCatalogMarkdownOverride
    }
}

extension Project: @unchecked Sendable {}
