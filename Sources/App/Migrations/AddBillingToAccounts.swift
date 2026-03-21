import Fluent

struct AddBillingToAccounts: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("accounts")
            .field("stripe_customer_id", .string)
            .field("stripe_subscription_id", .string)
            .field("subscription_status", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("accounts").deleteField("stripe_customer_id").update()
        try await database.schema("accounts").deleteField("stripe_subscription_id").update()
        try await database.schema("accounts").deleteField("subscription_status").update()
    }
}
