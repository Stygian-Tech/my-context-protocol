import Fluent

struct AddAgentHintsToRoutingRules: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("routing_rules")
            .field("failure_modes_json", .string)
            .field("invoke_first", .bool)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("routing_rules")
            .deleteField("failure_modes_json")
            .deleteField("invoke_first")
            .update()
    }
}
