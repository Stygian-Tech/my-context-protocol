import Fluent

struct AddNameToApiKeys: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("api_keys")
            .field("name", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("api_keys")
            .deleteField("name")
            .update()
    }
}
