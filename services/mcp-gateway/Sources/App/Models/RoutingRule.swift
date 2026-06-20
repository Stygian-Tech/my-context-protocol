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

    @OptionalField(key: "failure_modes_json")
    var failureModesJson: String?

    @OptionalField(key: "invoke_first")
    var invokeFirst: Bool?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        compiledSkillId: UUID,
        useWhenJson: String? = nil,
        avoidWhenJson: String? = nil,
        failureModesJson: String? = nil,
        invokeFirst: Bool? = nil
    ) {
        self.id = id
        self.$compiledSkill.id = compiledSkillId
        self.useWhenJson = useWhenJson
        self.avoidWhenJson = avoidWhenJson
        self.failureModesJson = failureModesJson
        self.invokeFirst = invokeFirst
    }
}

extension RoutingRule: @unchecked Sendable {}
