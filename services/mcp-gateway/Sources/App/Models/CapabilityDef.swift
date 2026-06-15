import Fluent
import Vapor

final class CapabilityDef: Model, Content {
    static let schema = "capability_defs"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "compiled_skill_id")
    var compiledSkill: CompiledSkill

    @Field(key: "capability_name")
    var capabilityName: String

    @Field(key: "type")
    var type: String

    @OptionalField(key: "schema_json")
    var schemaJson: String?

    @Field(key: "side_effect_level")
    var sideEffectLevel: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        compiledSkillId: UUID,
        capabilityName: String,
        type: String,
        schemaJson: String? = nil,
        sideEffectLevel: String
    ) {
        self.id = id
        self.$compiledSkill.id = compiledSkillId
        self.capabilityName = capabilityName
        self.type = type
        self.schemaJson = schemaJson
        self.sideEffectLevel = sideEffectLevel
    }
}

extension CapabilityDef: @unchecked Sendable {}
