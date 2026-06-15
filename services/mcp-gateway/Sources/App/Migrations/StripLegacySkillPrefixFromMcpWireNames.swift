import Fluent
import SQLKit

/// Strips the legacy `skill:` prefix from persisted MCP wire names so `capability_defs` and `tools_index`
/// match colon-free tool/prompt names exposed on the wire.
struct StripLegacySkillPrefixFromMcpWireNames: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw(
            """
            UPDATE capability_defs
            SET capability_name = SUBSTR(capability_name, 7)
            WHERE capability_name LIKE 'skill:%'
            """
        ).run()
        try await sql.raw(
            """
            UPDATE tools_index
            SET tool_name = SUBSTR(tool_name, 7)
            WHERE tool_name LIKE 'skill:%'
            """
        ).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw(
            """
            UPDATE capability_defs
            SET capability_name = 'skill:' || capability_name
            WHERE capability_name NOT LIKE 'skill:%'
            """
        ).run()
        try await sql.raw(
            """
            UPDATE tools_index
            SET tool_name = 'skill:' || tool_name
            WHERE tool_name NOT LIKE 'skill:%'
            """
        ).run()
    }
}
