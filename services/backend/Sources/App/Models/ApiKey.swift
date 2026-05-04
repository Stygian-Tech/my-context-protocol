import Fluent
import Vapor

final class ApiKey: Model, Content {
    static let schema = "api_keys"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "project_id")
    var project: Project

    @Field(key: "key_prefix")
    var keyPrefix: String

    @Field(key: "key_hash")
    var keyHash: String

    @OptionalField(key: "name")
    var name: String?

    @Field(key: "status")
    var status: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "last_used_at", on: .none)
    var lastUsedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        projectId: UUID,
        name: String? = nil,
        keyPrefix: String,
        keyHash: String,
        status: String = "active"
    ) {
        self.id = id
        self.$project.id = projectId
        self.name = name
        self.keyPrefix = keyPrefix
        self.keyHash = keyHash
        self.status = status
    }
}

extension ApiKey: @unchecked Sendable {}
