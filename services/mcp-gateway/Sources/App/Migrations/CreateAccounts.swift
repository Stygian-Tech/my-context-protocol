import Fluent

struct CreateAccounts: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("accounts")
            .id()
            .field("email", .string, .required)
            .field("password_hash", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "email")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("accounts").delete()
    }
}
