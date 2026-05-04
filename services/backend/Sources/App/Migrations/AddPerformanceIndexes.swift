import Fluent
import SQLKit

/// Adds indexes that are missing from initial table creation migrations.
///
/// Indexes added:
/// - `request_logs(project_id, timestamp DESC)` — every timeseries dashboard query filters by
///   project_id and sorts/ranges on timestamp; without this the planner does a full table scan.
/// - `api_keys(key_hash)` — looked up on every MCP request during bearer-token auth; the table is
///   small but the query is on the critical path and should never seq-scan.
/// - `compiled_skills(release_id, status)` — `MCPCatalogService.readyCompiledSkillIds` filters by
///   both columns on every MCP tools/list, resources/list, and prompts/list call.
struct AddPerformanceIndexes: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // Timeseries queries: WHERE project_id = ? AND timestamp BETWEEN ? AND ? ORDER BY timestamp
        try await sql.raw("""
            CREATE INDEX IF NOT EXISTS idx_request_logs_project_ts
            ON request_logs (project_id, timestamp DESC)
            """).run()

        // API key auth: WHERE key_hash = ? AND status = 'active'
        try await sql.raw("""
            CREATE INDEX IF NOT EXISTS idx_api_keys_hash
            ON api_keys (key_hash)
            """).run()

        // Catalog queries: WHERE release_id = ? AND status = 'ready'
        try await sql.raw("""
            CREATE INDEX IF NOT EXISTS idx_compiled_skills_release_status
            ON compiled_skills (release_id, status)
            """).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("DROP INDEX IF EXISTS idx_request_logs_project_ts").run()
        try await sql.raw("DROP INDEX IF EXISTS idx_api_keys_hash").run()
        try await sql.raw("DROP INDEX IF EXISTS idx_compiled_skills_release_status").run()
    }
}
