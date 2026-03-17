import Fluent
import Vapor

final class SkillPackage: Model, Content {
    static let schema = "skill_packages"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "release_id")
    var release: Release

    @Field(key: "path")
    var path: String

    @Field(key: "name")
    var name: String

    @OptionalField(key: "description")
    var description: String?

    @OptionalField(key: "hash")
    var hash: String?

    @Field(key: "validation_status")
    var validationStatus: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Children(for: \.$skillPackage)
    var toolsIndex: [ToolIndex]

    init() {}

    init(
        id: UUID? = nil,
        releaseId: UUID,
        path: String,
        name: String,
        description: String? = nil,
        hash: String? = nil,
        validationStatus: String = "valid"
    ) {
        self.id = id
        self.$release.id = releaseId
        self.path = path
        self.name = name
        self.description = description
        self.hash = hash
        self.validationStatus = validationStatus
    }
}

extension SkillPackage: @unchecked Sendable {}
