import Fluent

struct AddSuspendedAtToProjects: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("projects")
            .field("suspended_at", .datetime)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("suspended_at")
            .update()
    }
}
