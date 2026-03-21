import Fluent
import Vapor

final class RoutingRule: Model, Content {
    static let schema = "routing_rules"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "compiled_skill_id")
    var compiledSkill: CompiledSkill

    @OptionalField(key: "use_when_json")
    var useWhenJson: String?

    @OptionalField(key: "avoid_when_json")
    var avoidWhenJson: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        compiledSkillId: UUID,
        useWhenJson: String? = nil,
        avoidWhenJson: String? = nil
    ) {
        self.id = id
        self.$compiledSkill.id = compiledSkillId
        self.useWhenJson = useWhenJson
        self.avoidWhenJson = avoidWhenJson
    }
}

extension RoutingRule: @unchecked Sendable {}
