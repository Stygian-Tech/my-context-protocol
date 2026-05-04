import Fluent

struct AddBillingToAccounts: AsyncMigration {
    func prepare(on database: Database) async throws {
        // SQLite allows at most one ADD COLUMN per ALTER; Fluent otherwise emits invalid SQL.
        try await database.schema("accounts").field("stripe_customer_id", .string).update()
        try await database.schema("accounts").field("stripe_subscription_id", .string).update()
        try await database.schema("accounts").field("subscription_status", .string).update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("accounts").deleteField("stripe_customer_id").update()
        try await database.schema("accounts").deleteField("stripe_subscription_id").update()
        try await database.schema("accounts").deleteField("subscription_status").update()
    }
}
