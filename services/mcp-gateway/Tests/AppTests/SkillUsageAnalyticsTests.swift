import Fluent
import Foundation
import SQLKit
import Testing
import Vapor
@testable import App

@Suite("Per-skill usage analytics", .serialized)
struct SkillUsageAnalyticsTests {
    @Test("Consent off retains history, current zeros, legacy attribution and exact paginated counts")
    func aggregationAndRetention() async throws {
        try await withSkillUsageApp { app in
            let fixture = try await usageFixture(app)
            let observation = SkillUsageObservation(skill: fixture.skill, measurement: .surfaced, source: "test")
            await SkillUsageService.record(projectId: fixture.project.id!, clientIdentity: "client-a", events: [observation], db: app.db, logger: app.logger)
            #expect(try await SkillRuntimeEvent.query(on: app.db).filter(\.$project.$id == fixture.project.id!).count() == 0)
            fixture.settings.telemetryEnabled = true; try await fixture.settings.save(on: app.db)
            // More than the runtime diagnostics' 100-event sample, all counted in SQL.
            await SkillUsageService.record(projectId: fixture.project.id!, clientIdentity: "client-a", events: Array(repeating: observation, count: 125), db: app.db, logger: app.logger)
            // Exceed the 50,000-request transport sampling limit without issuing one insert per row.
            for start in stride(from: 0, to: 50_001, by: 500) {
                let events = (start..<min(start + 500, 50_001)).map { _ in
                    let event = SkillRuntimeEvent(); event.$project.id = fixture.project.id!; event.traceId = UUID()
                    event.eventType = "surfaced"; event.skillId = "review"; event.detailJson = "{}"
                    event.releaseId = fixture.skill.$release.id; event.skillVersion = fixture.skill.version; event.sourceChecksum = fixture.skill.sourceChecksum
                    return event
                }
                try await events.create(on: app.db)
            }
            let old = SkillRuntimeEvent(); old.$project.id = fixture.project.id!; old.traceId = UUID(); old.eventType = "skill_selected"
            old.skillId = "renamed-away"; old.detailJson = "{}"; try await old.save(on: app.db)
            let expired = SkillRuntimeEvent(); expired.$project.id = fixture.project.id!; expired.traceId = UUID(); expired.eventType = "surfaced"
            expired.skillId = "expired"; expired.detailJson = "{}"; try await expired.save(on: app.db)
            try await SkillRuntimeEvent.query(on: app.db).filter(\.$id == expired.id!).set(\.$createdAt, to: Date().addingTimeInterval(-31 * 86400)).update()
            fixture.settings.telemetryEnabled = false; try await fixture.settings.save(on: app.db)
            let result = try await SkillUsageAnalyticsService.read(project: fixture.project, query: .init(sort: "surfaced"), db: app.db)
            #expect(!result.collection_enabled)
            #expect(result.total == 3)
            #expect(result.skills.first?.counts.surfaced == 50_126)
            #expect(result.skills.first?.counts.agent_reported_skipped == 0)
            #expect(result.skills.first(where: { $0.skill_id == "unused" })?.counts.surfaced == 0)
            #expect(result.skills.first(where: { $0.skill_id == "renamed-away" })?.counts.legacy_resolver_selected == 1)
            #expect(result.skills.first(where: { $0.skill_id == "renamed-away" })?.is_current == false)
            let details = try await SkillUsageAnalyticsService.read(project: fixture.project, query: .init(skill_id: "renamed-away"), db: app.db)
            #expect(details.skills[0].versions[0].version == nil)
            #expect(details.skills[0].versions[0].counts.legacy_resolver_selected == 1)
            let beyond = try await SkillUsageAnalyticsService.read(project: fixture.project, query: .init(page: 99, page_size: 1), db: app.db)
            #expect(beyond.total == 3 && beyond.skills.isEmpty)
            await SkillUsageService.record(projectId: fixture.project.id!, clientIdentity: "client-a", events: [observation], db: app.db, logger: app.logger)
            #expect(try await SkillRuntimeEvent.query(on: app.db).filter(\.$project.$id == fixture.project.id!).count() == 50_128)
            let future = SkillRuntimeEvent(); future.$project.id = fixture.project.id!; future.traceId = UUID(); future.eventType = "surfaced"
            future.skillId = "future"; future.detailJson = "{}"; try await future.save(on: app.db)
            try await SkillRuntimeEvent.query(on: app.db).filter(\.$id == future.id!).set(\.$createdAt, to: Date().addingTimeInterval(86400)).update()
            let other = try await usageFixture(app)
            let foreign = SkillRuntimeEvent(); foreign.$project.id = other.project.id!; foreign.traceId = UUID(); foreign.eventType = "surfaced"
            foreign.skillId = "foreign"; foreign.detailJson = "{}"; try await foreign.save(on: app.db)
            let recent = try await ProjectController.recentRuntimeEvents(projectId: fixture.project.id!, retentionDays: 30, db: app.db)
            #expect(recent.count == 100)
            #expect(recent.allSatisfy { $0.$project.id == fixture.project.id! && !["expired", "future", "foreign"].contains($0.skillId ?? "") })
            let isolated = try await SkillUsageAnalyticsService.read(project: fixture.project, query: .init(), db: app.db)
            #expect(isolated.total == 3)
            try await SkillUsageService.prune(db: app.db)
            #expect(try await SkillRuntimeEvent.query(on: app.db).filter(\.$project.$id == fixture.project.id!).filter(\.$skillId == "expired").count() == 0)
        }
    }

    @Test("Reports validate project/client traces and versions; retries are idempotent")
    func reportValidationAndRetries() async throws {
        try await withSkillUsageApp { app in
            let fixture = try await usageFixture(app)
            let item = SkillUsageReportItem(skill_id: "review", version: "1.0.0", release_id: fixture.skill.$release.id, checksum: "abc", outcome: "skipped", skip_reason: "redundant")
            let input = SkillUsageReportInput(report_id: "batch-1", trace_id: nil, skills: [item])
            let disabled = try await SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "a", input: input, db: app.db)
            #expect(disabled.status == "collection_disabled")
            fixture.settings.telemetryEnabled = true; try await fixture.settings.save(on: app.db)
            let first = try await SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "a", input: input, db: app.db)
            let retry = try await SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "a", input: input, db: app.db)
            #expect(first.status == "recorded" && retry.status == "already_recorded")
            let conflicting = SkillUsageReportInput(report_id: "batch-1", trace_id: nil, skills: [.init(skill_id: "review", version: "1.0.0", release_id: nil, checksum: nil, outcome: "used", skip_reason: nil)])
            await #expect(throws: Abort.self) { try await SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "a", input: conflicting, db: app.db) }
            let invalid = SkillUsageReportInput(report_id: "invalid", trace_id: nil, skills: [.init(skill_id: "foreign", version: "1.0.0", release_id: nil, checksum: nil, outcome: "used", skip_reason: nil)])
            await #expect(throws: Abort.self) { try await SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "a", input: invalid, db: app.db) }
            let trace = UUID()
            await SkillUsageService.record(projectId: fixture.project.id!, clientIdentity: "a", events: [.init(traceId: trace, source: "resolve_skills")], db: app.db, logger: app.logger)
            let traced = SkillUsageReportInput(report_id: "traced", trace_id: trace, skills: [item])
            await #expect(throws: Abort.self) { try await SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "b", input: traced, db: app.db) }
            _ = try await SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "a", input: traced, db: app.db)
            // A different client owns a separate deduplication namespace.
            _ = try await SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "b", input: input, db: app.db)
            let details = try await SkillUsageAnalyticsService.read(project: fixture.project, query: .init(skill_id: "review"), db: app.db)
            #expect(details.skills[0].counts.agent_reported_skipped == 3)
            #expect(details.skills[0].agent_skip_reasons.first?.reason == "redundant")
            #expect(details.skills[0].versions.first?.version == "1.0.0")
            #expect(details.skills[0].versions.first?.checksum == "abc")
        }
    }

    @Test("Concurrent retry reserves one report and historical release remains attributable")
    func concurrentHistoricalReport() async throws {
        try await withSkillUsageApp { app in
            let fixture = try await usageFixture(app)
            fixture.settings.telemetryEnabled = true; try await fixture.settings.save(on: app.db)
            let historicalRelease = fixture.skill.$release.id
            let next = Release(projectId: fixture.project.id!, commitSha: "next", status: "ready"); try await next.save(on: app.db)
            fixture.project.activeReleaseId = next.id!; try await fixture.project.save(on: app.db)
            let input = SkillUsageReportInput(report_id: "concurrent", trace_id: nil, skills: [.init(skill_id: "review", version: "1.0.0", release_id: historicalRelease, checksum: nil, outcome: "used", skip_reason: nil)])
            async let one = SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "a", input: input, db: app.db)
            async let two = SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "a", input: input, db: app.db)
            let results = try await [one, two]
            #expect(Set(results.map(\.status)) == ["recorded", "already_recorded"])
            let result = try await SkillUsageAnalyticsService.read(project: fixture.project, query: .init(skill_id: "review"), db: app.db)
            #expect(result.skills[0].counts.agent_reported_used == 1)
            #expect(!result.skills[0].is_current)
            #expect(result.skills[0].versions[0].release_id == historicalRelease.uuidString)
        }
    }

    @Test("A batch permits distinct versions, rejects duplicate resolved references, and normalizes order")
    func multipleVersionReport() async throws {
        try await withSkillUsageApp { app in
            let fixture = try await usageFixture(app)
            fixture.settings.telemetryEnabled = true; try await fixture.settings.save(on: app.db)
            let next = Release(projectId: fixture.project.id!, commitSha: "next", status: "ready"); try await next.save(on: app.db)
            let package = SkillPackage(releaseId: next.id!, path: "review/SKILL.md", name: "review"); try await package.save(on: app.db)
            let updated = CompiledSkill(releaseId: next.id!, skillPackageId: package.id!, path: "review/SKILL.md", name: "Review", exposureType: "tool", riskLevel: "low", repoSpecific: false, status: "ready")
            updated.skillId = "review"; updated.version = "2.0.0"; updated.sourceChecksum = "new"; try await updated.save(on: app.db)
            let old = SkillUsageReportItem(skill_id: "review", version: "1.0.0", release_id: nil, checksum: nil, outcome: "used", skip_reason: nil)
            let new = SkillUsageReportItem(skill_id: "review", version: "2.0.0", release_id: nil, checksum: nil, outcome: "skipped", skip_reason: "task_changed")
            let first = try await SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "a", input: .init(report_id: "versions", trace_id: nil, skills: [new, old]), db: app.db)
            let retry = try await SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "a", input: .init(report_id: "versions", trace_id: nil, skills: [old, new]), db: app.db)
            #expect(first.recorded_count == 2 && retry.status == "already_recorded")
            let repeated = SkillUsageReportItem(skill_id: "review", version: "1.0.0", release_id: fixture.skill.$release.id, checksum: "abc", outcome: "used", skip_reason: nil)
            await #expect(throws: Abort.self) {
                try await SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "a", input: .init(report_id: "duplicate", trace_id: nil, skills: [old, repeated]), db: app.db)
            }
            #expect(try await SkillUsageReport.query(on: app.db).filter(\.$project.$id == fixture.project.id!).count() == 1)
        }
    }

    @Test("Persistence failures do not interrupt delivery and never acknowledge a report")
    func persistenceFailure() async throws {
        try await withSkillUsageApp { app in
            let fixture = try await usageFixture(app)
            fixture.settings.telemetryEnabled = true; try await fixture.settings.save(on: app.db)
            let sql = try #require(app.db as? any SQLDatabase)
            let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let name = "reject_usage_" + suffix
            let projectId = fixture.project.id!.uuidString
            if sql.dialect.name == "sqlite" {
                try await sql.raw(SQLQueryString("CREATE TRIGGER \(unsafeRaw: name) BEFORE INSERT ON skill_runtime_events WHEN NEW.project_id = '\(unsafeRaw: projectId)' BEGIN SELECT RAISE(ABORT, 'test persistence failure'); END")).run()
            } else {
                try await sql.raw(SQLQueryString("CREATE FUNCTION \(unsafeRaw: name)() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.project_id = '\(unsafeRaw: projectId)'::uuid THEN RAISE EXCEPTION 'test persistence failure'; END IF; RETURN NEW; END $$")).run()
                try await sql.raw(SQLQueryString("CREATE TRIGGER \(unsafeRaw: name) BEFORE INSERT ON skill_runtime_events FOR EACH ROW EXECUTE FUNCTION \(unsafeRaw: name)()")).run()
            }
            do {
                await SkillUsageService.record(projectId: fixture.project.id!, clientIdentity: "a", events: [.init(skill: fixture.skill, measurement: .instructionsDelivered, source: "test")], db: app.db, logger: app.logger)
                #expect(try await SkillRuntimeEvent.query(on: app.db).filter(\.$project.$id == fixture.project.id!).count() == 0)
                let input = SkillUsageReportInput(report_id: "failure", trace_id: nil, skills: [.init(skill_id: "review", version: "1.0.0", release_id: nil, checksum: nil, outcome: "used", skip_reason: nil)])
                var failed = false
                do { _ = try await SkillUsageService.report(projectId: fixture.project.id!, clientIdentity: "a", input: input, db: app.db) }
                catch { failed = true }
                #expect(failed)
                #expect(try await SkillUsageReport.query(on: app.db).filter(\.$project.$id == fixture.project.id!).count() == 0)
            } catch {
                try await removeUsageFailureTrigger(sql, name: name)
                throw error
            }
            try await removeUsageFailureTrigger(sql, name: name)
        }
    }

    @Test("Read windows honor shortened retention and reject malformed parameters")
    func windowValidation() async throws {
        try await withSkillUsageApp { app in
            let fixture = try await usageFixture(app)
            fixture.settings.telemetryRetentionDays = 1; try await fixture.settings.save(on: app.db)
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let response = try await SkillUsageAnalyticsService.read(project: fixture.project, query: .init(window: "30d"), db: app.db, now: now)
            let from = try #require(ISO8601DateFormatter().date(from: response.effective_from))
            #expect(now.timeIntervalSince(from) == 86400)
            for query in [SkillUsageQuery(window: "all"), .init(page: 0), .init(page_size: 101), .init(sort: "DROP"), .init(direction: "invalid")] {
                await #expect(throws: Abort.self) { try await SkillUsageAnalyticsService.read(project: fixture.project, query: query, db: app.db) }
            }
        }
    }
}

private struct UsageFixture: Sendable {
    let project: Project
    let skill: CompiledSkill
    let settings: ProjectRuntimeSettings
}
private func usageFixture(_ app: Application) async throws -> UsageFixture {
    let unique = UUID().uuidString.lowercased()
    let account = Account(githubId: Int64.random(in: 100_000_000...900_000_000), login: unique, email: "test@example.com"); try await account.save(on: app.db)
    let project = Project(accountId: account.id!, name: "Usage", slug: unique, subdomain: unique); try await project.save(on: app.db)
    let release = Release(projectId: project.id!, commitSha: "abc", status: "ready"); try await release.save(on: app.db)
    project.activeReleaseId = release.id!; try await project.save(on: app.db)
    let package = SkillPackage(releaseId: release.id!, path: "review/SKILL.md", name: "review"); try await package.save(on: app.db)
    let skill = CompiledSkill(releaseId: release.id!, skillPackageId: package.id!, path: "review/SKILL.md", name: "Review", exposureType: "tool", riskLevel: "low", repoSpecific: false, status: "ready")
    skill.skillId = "review"; skill.version = "1.0.0"; skill.sourceChecksum = "abc"; try await skill.save(on: app.db)
    let unused = CompiledSkill(releaseId: release.id!, skillPackageId: package.id!, path: "unused/SKILL.md", name: "Unused", exposureType: "tool", riskLevel: "low", repoSpecific: false, status: "ready")
    unused.skillId = "unused"; unused.version = "1.0.0"; try await unused.save(on: app.db)
    let settings = ProjectRuntimeSettings(); settings.$project.id = project.id!; settings.telemetryEnabled = false; settings.telemetryRetentionDays = 30
    settings.semanticEnabled = false; settings.feedbackIssueCreationEnabled = false; try await settings.save(on: app.db)
    return .init(project: project, skill: skill, settings: settings)
}
private func withSkillUsageApp(_ run: @Sendable @escaping (Application) async throws -> Void) async throws {
    try await TestProcessEnvGate.run {
        let keys = ["USE_SQLITE", "USE_MEMORY_SESSIONS", "DISABLE_SKILL_USAGE_RETENTION_SCHEDULER"]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, ProcessInfo.processInfo.environment[$0]) })
        unsetenv("USE_SQLITE"); setenv("USE_MEMORY_SESSIONS", "1", 1); setenv("DISABLE_SKILL_USAGE_RETENTION_SCHEDULER", "1", 1)
        defer { for key in keys { if let value = saved[key] ?? nil { setenv(key, value, 1) } else { unsetenv(key) } } }
        let app = try await Application.make(.testing)
        app.logger.logLevel = .warning
        do { try await configure(app); try await run(app) }
        catch { try await app.asyncShutdown(); throw error }
        try await app.asyncShutdown()
    }
}

private func removeUsageFailureTrigger(_ sql: any SQLDatabase, name: String) async throws {
    if sql.dialect.name == "sqlite" { try await sql.raw(SQLQueryString("DROP TRIGGER \(unsafeRaw: name)")).run() }
    else {
        try await sql.raw(SQLQueryString("DROP TRIGGER \(unsafeRaw: name) ON skill_runtime_events")).run()
        try await sql.raw(SQLQueryString("DROP FUNCTION \(unsafeRaw: name)()")).run()
    }
}
