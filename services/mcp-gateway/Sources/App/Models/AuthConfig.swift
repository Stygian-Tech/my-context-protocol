import Fluent
import Vapor

final class AuthConfig: Model, Content {
    static let schema = "auth_configs"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "project_id")
    var project: Project

    @Field(key: "mode")
    var mode: String

    @OptionalField(key: "settings_json")
    var settingsJson: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        projectId: UUID,
        mode: String = "api_key",
        settingsJson: String? = nil
    ) {
        self.id = id
        self.$project.id = projectId
        self.mode = mode
        self.settingsJson = settingsJson
    }
}

extension AuthConfig: @unchecked Sendable {}
