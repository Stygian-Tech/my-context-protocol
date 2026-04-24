import Fluent
import Vapor

final class McpOAuthClient: Model, Content {
    static let schema = "mcp_oauth_clients"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "public_client_id")
    var publicClientId: String

    @OptionalField(key: "client_secret_hash")
    var clientSecretHash: String?

    @Field(key: "is_confidential")
    var isConfidential: Bool

    @Field(key: "redirect_uris_json")
    var redirectUrisJson: String

    @Field(key: "allowed_grants")
    var allowedGrants: String

    @Field(key: "status")
    var status: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @OptionalParent(key: "project_id")
    var project: Project?

    init() {}

    init(
        id: UUID? = nil,
        publicClientId: String,
        clientSecretHash: String? = nil,
        isConfidential: Bool,
        redirectUrisJson: String,
        allowedGrants: String,
        status: String = "active",
        projectId: UUID? = nil
    ) {
        self.id = id
        self.publicClientId = publicClientId
        self.clientSecretHash = clientSecretHash
        self.isConfidential = isConfidential
        self.redirectUrisJson = redirectUrisJson
        self.allowedGrants = allowedGrants
        self.status = status
        self.$project.id = projectId
    }
}

extension McpOAuthClient: @unchecked Sendable {}
