import Fluent

struct CreateRequestLogs: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("request_logs")
            .id()
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            .field("release_id", .uuid, .references("releases", "id", onDelete: .setNull))
            .field("timestamp", .datetime)
            .field("client_id", .string)
            .field("method", .string, .required)
            .field("latency_ms", .int)
            .field("status", .string, .required)
            .field("error_code", .string)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("request_logs").delete()
    }
}
