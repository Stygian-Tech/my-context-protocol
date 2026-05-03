import Fluent
import Vapor

final class AppSessionRecord: Model, Content, @unchecked Sendable {
    static let schema = "app_sessions"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "session_key")
    var sessionKey: String

    @Field(key: "payload")
    var payload: String

    @OptionalField(key: "updated_at")
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, sessionKey: String, payload: String) {
        self.id = id
        self.sessionKey = sessionKey
        self.payload = payload
    }
}
