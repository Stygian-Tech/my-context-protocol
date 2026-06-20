import Fluent

struct AddProjectIdToMcpOauthClients: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("mcp_oauth_clients")
            .field("project_id", .uuid, .references("projects", "id", onDelete: .setNull))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("mcp_oauth_clients")
            .deleteField("project_id")
            .update()
    }
}
