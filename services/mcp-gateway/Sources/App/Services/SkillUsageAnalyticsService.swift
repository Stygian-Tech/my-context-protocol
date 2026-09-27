import Fluent
import SQLKit
import Vapor

struct SkillUsageQuery: Content, Sendable {
    var window: String? = nil
    var page: Int? = nil
    var page_size: Int? = nil
    var sort: String? = nil
    var direction: String? = nil
    var skill_id: String? = nil
}

enum SkillUsageAnalyticsService {
    private static let eventColumns = ["surfaced", "instructions_delivered", "supporting_file_read", "resolver_selected", "resolver_suggested", "resolver_excluded", "agent_reported_used", "agent_reported_skipped", "legacy_resolver_selected"]

    static func read(project: Project, query: SkillUsageQuery, db: Database, now: Date = Date()) async throws -> SkillUsageResponse {
        guard let projectId = project.id, let sql = db as? any SQLDatabase else { throw Abort(.internalServerError) }
        let window = query.window ?? "7d"
        guard let days = ["24h": 1, "7d": 7, "30d": 30][window] else { throw Abort(.badRequest, reason: "window must be 24h, 7d, or 30d") }
        let page = query.page ?? 1, size = query.page_size ?? 25
        guard (1...1_000_000).contains(page), (1...100).contains(size) else { throw Abort(.badRequest, reason: "Invalid pagination") }
        let sort = query.sort ?? "activity", direction = query.direction ?? "desc"
        guard ["activity", "skill_id", "surfaced", "instructions_delivered", "agent_reported_used", "agent_reported_skipped"].contains(sort),
              ["asc", "desc"].contains(direction) else { throw Abort(.badRequest, reason: "Invalid sort") }
        if let id = query.skill_id, id.isEmpty || id.utf8.count > 256 { throw Abort(.badRequest, reason: "Invalid skill_id") }
        let settings = try await ProjectRuntimeSettings.query(on: db).filter(\.$project.$id == projectId).first()
        let retention = max(1, settings?.telemetryRetentionDays ?? 30)
        let cutoff = now.addingTimeInterval(-Double(min(days, retention)) * 86400)
        var base: SQLQueryString = """
        WITH recent AS (
          SELECT * FROM skill_runtime_events WHERE project_id = \(bind: projectId)
            AND created_at >= \(bind: cutoff) AND created_at <= \(bind: now) AND skill_id IS NOT NULL
        ), current_skills AS (
          SELECT COALESCE(skill_id, name) AS skill_id, MAX(name) AS name FROM compiled_skills
          WHERE release_id = \(bind: project.activeReleaseId ?? UUID()) AND status = 'ready'
          GROUP BY COALESCE(skill_id, name)
        ), identities AS (
          SELECT skill_id FROM recent UNION SELECT skill_id FROM current_skills
        ), filtered AS (SELECT skill_id FROM identities
        """
        if let skillId = query.skill_id { base.appendInterpolation(SQLQueryString(" WHERE skill_id = \(bind: skillId)")) }
        base.appendLiteral(") ")
        let totalRow = try await sql.raw("\(base) SELECT COUNT(*) AS total FROM filtered").first()
        let total = try totalRow?.decode(column: "total", as: Int.self) ?? 0
        let sums = eventColumns.map { column in
            "COALESCE(SUM(CASE WHEN recent.event_type = '\(column == "legacy_resolver_selected" ? "skill_selected" : column)' THEN 1 ELSE 0 END), 0) AS \(column)"
        }.joined(separator: ", ")
        let sortColumn = sort == "activity" ? "last_activity" : sort == "skill_id" ? "filtered.skill_id" : sort
        let rows = try await sql.raw("""
        \(base) SELECT filtered.skill_id, COALESCE(MAX(current_skills.name), filtered.skill_id) AS name,
          CASE WHEN MAX(current_skills.skill_id) IS NULL THEN 0 ELSE 1 END AS is_current,
          MAX(recent.created_at) AS last_activity, \(unsafeRaw: sums)
        FROM filtered LEFT JOIN recent ON recent.skill_id = filtered.skill_id
          LEFT JOIN current_skills ON current_skills.skill_id = filtered.skill_id
        GROUP BY filtered.skill_id
        ORDER BY \(unsafeRaw: sort == "activity" ? "CASE WHEN MAX(recent.created_at) IS NULL THEN 1 ELSE 0 END," : "")
          \(unsafeRaw: sortColumn) \(unsafeRaw: direction.uppercased()), filtered.skill_id ASC
        LIMIT \(bind: size) OFFSET \(bind: (page - 1) * size)
        """).all()
        var skills: [SkillUsageRow] = try rows.map { row in
            let date = try row.decode(column: "last_activity", as: Date?.self)
            return SkillUsageRow(skill_id: try row.decode(column: "skill_id", as: String.self),
                name: try row.decode(column: "name", as: String.self), is_current: try row.decode(column: "is_current", as: Int.self) == 1,
                last_activity: date.map(iso), counts: try counts(row), versions: [], resolver_exclusion_reasons: [], agent_skip_reasons: [])
        }
        if let skillId = query.skill_id, !skills.isEmpty {
            let versions = try await sql.raw("""
            SELECT release_id, skill_version, source_checksum, \(unsafeRaw: sums.replacingOccurrences(of: "recent.event_type", with: "event_type"))
            FROM skill_runtime_events WHERE project_id = \(bind: projectId) AND skill_id = \(bind: skillId)
              AND created_at >= \(bind: cutoff) AND created_at <= \(bind: now)
            GROUP BY release_id, skill_version, source_checksum ORDER BY MAX(created_at) DESC
            """).all()
            skills[0].versions = try versions.map { row in
                .init(release_id: try row.decode(column: "release_id", as: UUID?.self)?.uuidString,
                      version: try row.decode(column: "skill_version", as: String?.self),
                      checksum: try row.decode(column: "source_checksum", as: String?.self), counts: try counts(row))
            }
            let reasons = try await sql.raw("""
            SELECT event_type, reason_code, COUNT(*) AS count FROM skill_runtime_events
            WHERE project_id = \(bind: projectId) AND skill_id = \(bind: skillId)
              AND created_at >= \(bind: cutoff) AND created_at <= \(bind: now)
              AND event_type IN ('resolver_excluded', 'agent_reported_skipped') AND reason_code IS NOT NULL
            GROUP BY event_type, reason_code ORDER BY COUNT(*) DESC, reason_code ASC
            """).all()
            for row in reasons {
                let reason = SkillUsageReason(reason: try row.decode(column: "reason_code", as: String.self), count: try row.decode(column: "count", as: Int.self))
                if try row.decode(column: "event_type", as: String.self) == "resolver_excluded" { skills[0].resolver_exclusion_reasons.append(reason) }
                else { skills[0].agent_skip_reasons.append(reason) }
            }
        }
        return .init(collection_enabled: settings?.telemetryEnabled ?? false, retention_days: retention, requested_window: window,
                     effective_from: iso(cutoff), effective_to: iso(now), reporting_coverage: "partial", historical_measurements: "legacy_resolver_only",
                     page: page, page_size: size, total: total, skills: skills)
    }

    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func counts(_ row: any SQLRow) throws -> SkillUsageCounts {
        .init(surfaced: try row.decode(column: "surfaced", as: Int.self), instructions_delivered: try row.decode(column: "instructions_delivered", as: Int.self),
              supporting_file_read: try row.decode(column: "supporting_file_read", as: Int.self), resolver_selected: try row.decode(column: "resolver_selected", as: Int.self),
              resolver_suggested: try row.decode(column: "resolver_suggested", as: Int.self), resolver_excluded: try row.decode(column: "resolver_excluded", as: Int.self),
              agent_reported_used: try row.decode(column: "agent_reported_used", as: Int.self), agent_reported_skipped: try row.decode(column: "agent_reported_skipped", as: Int.self),
              legacy_resolver_selected: try row.decode(column: "legacy_resolver_selected", as: Int.self))
    }
}
