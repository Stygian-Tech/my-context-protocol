import Fluent

struct AddAgentHintsToRoutingRules: AsyncMigration {
    func prepare(on database: Database) async throws {
        // SQLite allows at most one ADD COLUMN per ALTER; Fluent otherwise emits invalid SQL.
        try await database.schema("routing_rules").field("failure_modes_json", .string).update()
        try await database.schema("routing_rules").field("invoke_first", .bool).update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("routing_rules").deleteField("failure_modes_json").update()
        try await database.schema("routing_rules").deleteField("invoke_first").update()
    }
}
