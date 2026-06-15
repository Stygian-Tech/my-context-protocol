import Fluent

struct AddRequestLogErrorMessage: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("request_logs")
            .field("error_message", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("request_logs")
            .deleteField("error_message")
            .update()
    }
}
