import Fluent
import SQLKit

/// When each account-level override was last turned on (nil while off). Used for admin audit UI.
struct AddAccountPrivilegeGrantedAt: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("accounts")
            .field("admin_granted_at", .datetime)
            .update()
        try await database.schema("accounts")
            .field("paywall_bypass_granted_at", .datetime)
            .update()

        guard let sql = database as? any SQLDatabase else { return }
        try await sql.raw(
            """
            UPDATE accounts SET admin_granted_at = created_at
            WHERE is_admin = true AND admin_granted_at IS NULL
            """
        ).run()
        try await sql.raw(
            """
            UPDATE accounts SET paywall_bypass_granted_at = created_at
            WHERE paywall_bypass = true AND paywall_bypass_granted_at IS NULL
            """
        ).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("accounts").deleteField("admin_granted_at").update()
        try await database.schema("accounts").deleteField("paywall_bypass_granted_at").update()
    }
}
