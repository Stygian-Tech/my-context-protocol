import Fluent
import Vapor

/// No-op for OAuth-only: users sign in via GitHub OAuth and create projects through the API.
struct SeedPersonalUse: AsyncMigration {
    func prepare(on database: Database) async throws {
        // OAuth-only: no pre-seeded accounts
    }

    func revert(on database: Database) async throws {
        // No-op
    }
}
