import Crypto
import Fluent
import FluentSQLiteDriver
import Vapor

enum SkillUsageMeasurement: String, Codable, CaseIterable, Sendable {
    case surfaced, instructionsDelivered = "instructions_delivered", supportingFileRead = "supporting_file_read"
    case resolverSelected = "resolver_selected", resolverSuggested = "resolver_suggested", resolverExcluded = "resolver_excluded"
    case agentReportedUsed = "agent_reported_used", agentReportedSkipped = "agent_reported_skipped"
}

struct SkillUsageObservation: Sendable {
    let skillId: String?
    let releaseId: UUID?
    let version: String?
    let checksum: String?
    let eventType: String
    let source: String
    let traceId: UUID
    let reason: String?

    init(skill: CompiledSkill, measurement: SkillUsageMeasurement, source: String, traceId: UUID? = nil, reason: String? = nil) {
        skillId = skill.skillId ?? skill.name; releaseId = skill.$release.id; version = skill.version
        checksum = skill.sourceChecksum; eventType = measurement.rawValue; self.source = source
        self.traceId = traceId ?? UUID(); self.reason = reason
    }
    init(traceId: UUID, source: String) {
        skillId = nil; releaseId = nil; version = nil; checksum = nil; reason = nil
        eventType = "resolution_trace"; self.source = source; self.traceId = traceId
    }
}

struct SkillUsageReportItem: Codable, Sendable {
    let skill_id: String
    let version: String
    let release_id: UUID?
    let checksum: String?
    let outcome: String
    let skip_reason: String?
}
struct SkillUsageReportInput: Codable, Sendable {
    let report_id: String
    let trace_id: UUID?
    let skills: [SkillUsageReportItem]
}
struct SkillUsageReportResult: Content, Sendable {
    let status: String
    let recorded_count: Int
}

enum SkillUsageService {
    static let skipReasons: Set<String> = ["not_relevant", "redundant", "instruction_conflict", "missing_capability", "task_changed", "other"]

    static func record(projectId: UUID, clientIdentity: String, events: [SkillUsageObservation], db: Database, logger: Logger) async {
        guard !events.isEmpty else { return }
        do {
            try await db.transaction { transaction in
                guard let settings = try await ProjectRuntimeSettings.query(on: transaction).filter(\.$project.$id == projectId).first(), settings.telemetryEnabled else { return }
                let rows = events.map { event(projectId: projectId, clientIdentity: clientIdentity, observation: $0) }
                // Bound bind counts on both databases and avoid a round trip for every catalog result.
                for offset in stride(from: 0, to: rows.count, by: 250) {
                    try await Array(rows[offset..<min(offset + 250, rows.count)]).create(on: transaction)
                }
            }
        } catch {
            // Avoid logging request or agent-controlled contents.
            logger.error("Skill usage telemetry persistence failed", metadata: ["project_id": .string(projectId.uuidString)])
        }
    }

    private static func event(projectId: UUID, clientIdentity: String, observation: SkillUsageObservation) -> SkillRuntimeEvent {
        let event = SkillRuntimeEvent()
        event.$project.id = projectId; event.traceId = observation.traceId; event.eventType = observation.eventType
        event.skillId = observation.skillId; event.releaseId = observation.releaseId; event.skillVersion = observation.version
        event.sourceChecksum = observation.checksum; event.clientIdentity = clientIdentity; event.source = observation.source
        event.reasonCode = observation.reason; event.detailJson = "{}"
        return event
    }

    static func report(projectId: UUID, clientIdentity: String, input: SkillUsageReportInput, db: Database) async throws -> SkillUsageReportResult {
        // SQLite deferred transactions can collide before the unique reservation is visible.
        // Retry the whole rolled-back transaction, never acknowledge an uncommitted report.
        for attempt in 0...4 {
            do { return try await reportAttempt(projectId: projectId, clientIdentity: clientIdentity, input: input, db: db) }
            catch let error as SQLiteError {
                let retryable: Bool
                switch error.reason {
                case .busy, .locked, .busyInRecovery, .busyInSnapshot, .busyTimeout, .lockedBySharedCache: retryable = true
                default: retryable = false
                }
                guard retryable, attempt < 4 else { throw error }
                try await Task.sleep(for: .milliseconds(25 * (attempt + 1)))
            }
        }
        throw Abort(.serviceUnavailable, reason: "Usage reporting is temporarily unavailable")
    }

    private static func reportAttempt(projectId: UUID, clientIdentity: String, input: SkillUsageReportInput, db: Database) async throws -> SkillUsageReportResult {
        guard !clientIdentity.isEmpty, !input.report_id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, input.report_id.utf8.count <= 128,
              (1...100).contains(input.skills.count) else { throw Abort(.badRequest, reason: "Provide a report ID of at most 128 bytes and 1–100 skill outcomes") }
        for item in input.skills {
            guard !item.skill_id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.skill_id.utf8.count <= 128, !item.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.version.utf8.count <= 512,
                  item.checksum.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 128 }) ?? true,
                  ["used", "skipped"].contains(item.outcome),
                  item.outcome == "skipped" ? skipReasons.contains(item.skip_reason ?? "") : item.skip_reason == nil else {
                throw Abort(.badRequest, reason: "Report each skill version once, with a valid version, outcome, and categorized skip reason only when skipped")
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let normalized = SkillUsageReportInput(report_id: input.report_id, trace_id: input.trace_id, skills: input.skills.sorted { reportItemSortKey($0) < reportItemSortKey($1) })
        let digest = SHA256.hash(data: try encoder.encode(normalized)).map { String(format: "%02x", $0) }.joined()
        // Treat caller-chosen IDs as opaque: retain a digest rather than potentially sensitive text.
        let reportKey = SHA256.hash(data: Data(input.report_id.utf8)).map { String(format: "%02x", $0) }.joined()
        do {
            return try await db.transaction { transaction in
                guard let settings = try await ProjectRuntimeSettings.query(on: transaction).filter(\.$project.$id == projectId).first(), settings.telemetryEnabled else {
                    return .init(status: "collection_disabled", recorded_count: 0)
                }
                let cutoff = Date().addingTimeInterval(-Double(max(1, settings.telemetryRetentionDays)) * 86400)
                if let existing = try await existingReport(projectId: projectId, client: clientIdentity, reportId: reportKey, cutoff: cutoff, db: transaction) {
                    return try duplicate(existing, digest: digest)
                }
                if let traceId = input.trace_id {
                    guard try await SkillRuntimeEvent.query(on: transaction).filter(\.$project.$id == projectId)
                        .filter(\.$clientIdentity == clientIdentity).filter(\.$traceId == traceId)
                        .filter(\.$eventType == "resolution_trace").filter(\.$createdAt >= cutoff).filter(\.$createdAt <= Date()).first() != nil else {
                        throw Abort(.badRequest, reason: "Resolution trace is unavailable for this project and client")
                    }
                }
                var observations: [SkillUsageObservation] = []
                var resolvedIdentities = Set<String>()
                for item in input.skills {
                    let query = CompiledSkill.query(on: transaction).join(Release.self, on: \CompiledSkill.$release.$id == \Release.$id)
                        .filter(Release.self, \.$project.$id == projectId).filter(\.$skillId == item.skill_id).filter(\.$version == item.version).filter(\.$status == "ready")
                    if let release = item.release_id { query.filter(\.$release.$id == release) }
                    if let checksum = item.checksum { query.filter(\.$sourceChecksum == checksum) }
                    var candidates = try await query.sort(\.$createdAt, .descending).all()
                    // A trace is a stronger attribution source than the newest release for the same version.
                    if item.release_id == nil, let traceId = input.trace_id {
                        let tracedEvents = try await SkillRuntimeEvent.query(on: transaction).filter(\.$project.$id == projectId)
                            .filter(\.$clientIdentity == clientIdentity).filter(\.$traceId == traceId).filter(\.$skillId == item.skill_id)
                            .filter(\.$skillVersion == item.version).filter(\.$createdAt >= cutoff).all()
                        let tracedReleases = Set(tracedEvents.compactMap(\.releaseId))
                        let tracedCandidates = candidates.filter { tracedReleases.contains($0.$release.id) }
                        if !tracedCandidates.isEmpty { candidates = tracedCandidates }
                    }
                    guard let skill = candidates.first else { throw Abort(.badRequest, reason: "Skill version is not present in this project's releases") }
                    guard Set(candidates.map { $0.sourceChecksum ?? "" }).count <= 1 else {
                        throw Abort(.badRequest, reason: "Skill version is ambiguous; provide release_id or checksum")
                    }
                    let resolvedIdentity = [item.skill_id, item.version, skill.$release.id.uuidString, skill.sourceChecksum ?? ""].joined(separator: "\u{0}")
                    guard resolvedIdentities.insert(resolvedIdentity).inserted else {
                        throw Abort(.badRequest, reason: "Report each resolved skill version and release only once")
                    }
                    observations.append(.init(skill: skill, measurement: item.outcome == "used" ? .agentReportedUsed : .agentReportedSkipped,
                                              source: "report_skill_usage", traceId: input.trace_id, reason: item.skip_reason))
                }
                // Remove an expired deduplication key before reserving the new report.
                try await SkillUsageReport.query(on: transaction).filter(\.$project.$id == projectId).filter(\.$clientIdentity == clientIdentity)
                    .filter(\.$reportId == reportKey).filter(\.$createdAt < cutoff).delete()
                let report = SkillUsageReport(); report.$project.id = projectId; report.clientIdentity = clientIdentity
                report.reportId = reportKey; report.payloadHash = digest; report.recordedCount = observations.count
                try await report.create(on: transaction)
                let rows = observations.map { event(projectId: projectId, clientIdentity: clientIdentity, observation: $0) }
                try await rows.create(on: transaction)
                return .init(status: "recorded", recorded_count: observations.count)
            }
        } catch {
            // A concurrent unique-key winner is read outside the failed transaction (Postgres aborts it).
            if error is Abort { throw error }
            let settings = try await ProjectRuntimeSettings.query(on: db).filter(\.$project.$id == projectId).first()
            let cutoff = Date().addingTimeInterval(-Double(max(1, settings?.telemetryRetentionDays ?? 30)) * 86400)
            if let existing = try await existingReport(projectId: projectId, client: clientIdentity, reportId: reportKey, cutoff: cutoff, db: db) {
                return try duplicate(existing, digest: digest)
            }
            throw error
        }
    }

    private static func reportItemSortKey(_ item: SkillUsageReportItem) -> String {
        [item.skill_id, item.version, item.release_id?.uuidString ?? "", item.checksum ?? "", item.outcome, item.skip_reason ?? ""].joined(separator: "\u{0}")
    }

    private static func duplicate(_ report: SkillUsageReport, digest: String) throws -> SkillUsageReportResult {
        guard report.payloadHash == digest else { throw Abort(.conflict, reason: "Report ID was already used for different skill outcomes") }
        return .init(status: "already_recorded", recorded_count: report.recordedCount)
    }
    private static func existingReport(projectId: UUID, client: String, reportId: String, cutoff: Date, db: Database) async throws -> SkillUsageReport? {
        try await SkillUsageReport.query(on: db).filter(\.$project.$id == projectId).filter(\.$clientIdentity == client)
            .filter(\.$reportId == reportId).filter(\.$createdAt >= cutoff).first()
    }

    static func prune(db: Database, now: Date = Date()) async throws {
        // Include inactive projects and projects whose consent has since been disabled.
        for project in try await Project.query(on: db).all() {
            guard let projectId = project.id else { continue }
            let settings = try await ProjectRuntimeSettings.query(on: db).filter(\.$project.$id == projectId).first()
            let cutoff = now.addingTimeInterval(-Double(max(1, settings?.telemetryRetentionDays ?? 30)) * 86400)
            try await SkillRuntimeEvent.query(on: db).filter(\.$project.$id == projectId).filter(\.$createdAt < cutoff).delete()
            try await SkillUsageReport.query(on: db).filter(\.$project.$id == projectId).filter(\.$createdAt < cutoff).delete()
        }
    }
}
