import Fluent

struct CreateAppSessions: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("app_sessions")
            .field("id", .uuid, .identifier(auto: true))
            .field("session_key", .string, .required)
            .field("payload", .string, .required)
            .field("updated_at", .datetime)
            .unique(on: "session_key")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("app_sessions").delete()
    }
}
