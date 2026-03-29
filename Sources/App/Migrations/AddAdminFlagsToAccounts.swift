import Fluent

struct AddAdminFlagsToAccounts: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("accounts").field("is_admin", .bool, .required, .sql(.default(false))).update()
        try await database.schema("accounts").field("paywall_bypass", .bool, .required, .sql(.default(false))).update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("accounts").deleteField("is_admin").update()
        try await database.schema("accounts").deleteField("paywall_bypass").update()
    }
}
