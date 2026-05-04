import Fluent

struct AddMcpCatalogMarkdownOverrideToProjects: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("projects")
            .field("mcp_catalog_markdown_override", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("mcp_catalog_markdown_override")
            .update()
    }
}
