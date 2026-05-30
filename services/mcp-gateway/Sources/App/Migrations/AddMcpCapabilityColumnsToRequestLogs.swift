import Fluent

struct AddMcpCapabilityColumnsToRequestLogs: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(RequestLog.schema)
            .field("mcp_capability_kind", .string)
            .update()
        try await database.schema(RequestLog.schema)
            .field("mcp_capability_key", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(RequestLog.schema)
            .deleteField("mcp_capability_key")
            .update()
        try await database.schema(RequestLog.schema)
            .deleteField("mcp_capability_kind")
            .update()
    }
}
