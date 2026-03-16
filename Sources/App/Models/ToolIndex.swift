import Fluent
import Vapor

final class ToolIndex: Model, Content {
    static let schema = "tools_index"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "skill_package_id")
    var skillPackage: SkillPackage

    @Field(key: "tool_name")
    var toolName: String

    @OptionalField(key: "schema_json")
    var schemaJson: String?

    @Field(key: "handler_type")
    var handlerType: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        skillPackageId: UUID,
        toolName: String,
        schemaJson: String? = nil,
        handlerType: String
    ) {
        self.id = id
        self.$skillPackage.id = skillPackageId
        self.toolName = toolName
        self.schemaJson = schemaJson
        self.handlerType = handlerType
    }
}
