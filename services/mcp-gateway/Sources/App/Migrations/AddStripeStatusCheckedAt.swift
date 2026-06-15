import Fluent

struct AddStripeStatusCheckedAt: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("accounts")
            .field("stripe_status_checked_at", .datetime)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("accounts")
            .deleteField("stripe_status_checked_at")
            .update()
    }
}
