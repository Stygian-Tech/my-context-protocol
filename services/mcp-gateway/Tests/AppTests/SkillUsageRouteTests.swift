import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

@Suite("Skill usage dashboard route", .serialized)
struct SkillUsageRouteTests {
    @Test("Browser sessions enforce project ownership and validate analytics queries")
    func authorizationAndQueries() async throws {
        try await withSkillUsageRouteApp { app in
            let suffix = UUID().uuidString.lowercased()
            let owner = Account(githubId: Int64.random(in: 100_000_000...900_000_000), login: "owner-" + suffix)
            let stranger = Account(githubId: Int64.random(in: 100_000_000...900_000_000), login: "stranger-" + suffix)
            try await owner.save(on: app.db)
            try await stranger.save(on: app.db)
            let project = Project(accountId: owner.id!, name: "Usage route", slug: suffix, subdomain: suffix)
            try await project.save(on: app.db)
            let release = Release(projectId: project.id!, commitSha: "route-test", status: "ready")
            try await release.save(on: app.db)
            let package = SkillPackage(releaseId: release.id!, path: "review/SKILL.md", name: "review")
            try await package.save(on: app.db)
            let skill = CompiledSkill(releaseId: release.id!, skillPackageId: package.id!, path: package.path,
                name: "Review", exposureType: "resource", riskLevel: "low", repoSpecific: false, status: "ready")
            skill.skillId = "review"; skill.version = "1.0.0"; skill.sourceChecksum = "abc"
            try await skill.save(on: app.db)
            project.activeReleaseId = release.id
            try await project.save(on: app.db)
            let path = "/projects/\(project.id!)/skill-usage"

            func cookie(for account: Account) async throws -> String {
                let request = Request(application: app, method: .GET, url: URI(path: path),
                    version: .http1_1, headers: [:], remoteAddress: nil, logger: app.logger,
                    on: app.eventLoopGroup.next())
                let id = try await app.sessions.driver.createSession(["accountId": account.id!.uuidString], for: request).get()
                return "\(app.sessions.configuration.cookieName)=\(id.string)"
            }
            let ownerCookie = try await cookie(for: owner)
            let strangerCookie = try await cookie(for: stranger)
            try await app.testing().test(.GET, path, afterResponse: { response in
                #expect(response.status == .unauthorized)
            })
            try await app.testing().test(.GET, path, beforeRequest: { request in
                request.headers.replaceOrAdd(name: .cookie, value: strangerCookie)
            }, afterResponse: { response in
                #expect(response.status == .notFound)
            })
            try await app.testing().test(.GET, path, beforeRequest: { request in
                request.headers.replaceOrAdd(name: .cookie, value: ownerCookie)
            }, afterResponse: { response in
                #expect(response.status == .ok)
                let result = try JSONDecoder().decode(SkillUsageResponse.self, from: Data(response.body.string.utf8))
                #expect(result.collection_enabled == false)
                #expect(result.retention_days == 30)
                #expect(result.requested_window == "7d")
                #expect(result.reporting_coverage == "partial")
                #expect(result.historical_measurements == "legacy_resolver_only")
                #expect(result.total == 1)
                #expect(result.skills.first?.skill_id == "review")
                #expect(result.skills.first?.counts.surfaced == 0)
                #expect(result.skills.first?.counts.agent_reported_skipped == 0)
            })
            try await app.testing().test(.GET,
                path + "?window=24h&page=1&page_size=1&sort=skill_id&direction=asc&skill_id=review",
                beforeRequest: { request in request.headers.replaceOrAdd(name: .cookie, value: ownerCookie) },
                afterResponse: { response in
                    #expect(response.status == .ok)
                    let result = try JSONDecoder().decode(SkillUsageResponse.self, from: Data(response.body.string.utf8))
                    #expect(result.requested_window == "24h")
                    #expect(result.page == 1 && result.page_size == 1 && result.total == 1)
                    #expect(result.skills.first?.versions.isEmpty == true)
                })
            for query in ["window=all", "page=0", "page=nope", "page_size=101", "sort=unknown", "direction=sideways"] {
                try await app.testing().test(.GET, path + "?" + query,
                    beforeRequest: { request in request.headers.replaceOrAdd(name: .cookie, value: ownerCookie) },
                    afterResponse: { response in #expect(response.status == .badRequest) })
            }
            // Analytics reads must not create or change editable runtime settings.
            #expect(try await ProjectRuntimeSettings.query(on: app.db).filter(\.$project.$id == project.id!).count() == 0)
        }
    }

    @Test("Runtime settings serialize snake_case assignments and events, and saved assignments round-trip")
    func runtimeSettingsWireShape() async throws {
        try await withSkillUsageRouteApp { app in
            let suffix = UUID().uuidString.lowercased()
            let owner = Account(githubId: Int64.random(in: 100_000_000...900_000_000), login: "runtime-" + suffix)
            try await owner.save(on: app.db)
            let project = Project(accountId: owner.id!, name: "Runtime route", slug: suffix, subdomain: suffix)
            try await project.save(on: app.db)
            let release = Release(projectId: project.id!, commitSha: "runtime-test", status: "ready")
            try await release.save(on: app.db)
            let package = SkillPackage(releaseId: release.id!, path: "review/SKILL.md", name: "review")
            try await package.save(on: app.db)
            let skill = CompiledSkill(releaseId: release.id!, skillPackageId: package.id!, path: package.path,
                name: "Review", exposureType: "resource", riskLevel: "low", repoSpecific: false, status: "ready")
            skill.skillId = "review"; skill.version = "1.0.0"; skill.sourceChecksum = "abc"
            try await skill.save(on: app.db)
            project.activeReleaseId = release.id
            try await project.save(on: app.db)

            let assignment = SkillAssignment()
            assignment.$project.id = project.id!
            assignment.skillId = "review"; assignment.scope = "repository"; assignment.activationMode = "always"
            assignment.targetType = "repository"; assignment.targetId = "stygian/app"
            assignment.required = true; assignment.priority = 50
            try await assignment.save(on: app.db)

            let traceId = UUID()
            let event = SkillRuntimeEvent()
            event.$project.id = project.id!
            event.traceId = traceId; event.eventType = "instruction_delivery"
            event.detailJson = #"{"private":true}"#; event.requestHash = "hash-secret"; event.clientIdentity = "client-secret"
            try await event.save(on: app.db)

            let path = "/projects/\(project.id!)/skill-runtime"
            let request = Request(application: app, method: .GET, url: URI(path: path),
                version: .http1_1, headers: [:], remoteAddress: nil, logger: app.logger, on: app.eventLoopGroup.next())
            let sessionId = try await app.sessions.driver.createSession(["accountId": owner.id!.uuidString], for: request).get()
            let cookie = "\(app.sessions.configuration.cookieName)=\(sessionId.string)"

            var savedAssignments: [[String: Any]] = []
            try await app.testing().test(.GET, path, beforeRequest: { request in
                request.headers.replaceOrAdd(name: .cookie, value: cookie)
            }, afterResponse: { response in
                #expect(response.status == .ok)
                let json = try #require(try JSONSerialization.jsonObject(with: Data(response.body.string.utf8)) as? [String: Any])
                let assignments = try #require(json["assignments"] as? [[String: Any]])
                #expect(assignments.count == 1)
                let saved = try #require(assignments.first)
                #expect(Set(saved.keys) == ["id", "skill_id", "scope", "activation_mode", "target_type", "target_id", "required", "priority"])
                #expect(saved["skill_id"] as? String == "review")
                #expect(saved["activation_mode"] as? String == "always")
                #expect(saved["target_id"] as? String == "stygian/app")
                savedAssignments = assignments

                let events = try #require(json["recent_events"] as? [[String: Any]])
                let first = try #require(events.first)
                #expect(first["trace_id"] as? String == traceId.uuidString)
                #expect(first["event_type"] as? String == "instruction_delivery")
                #expect(first["skill_id"] == nil || first["skill_id"] is NSNull)
                #expect(first["reason_code"] == nil || first["reason_code"] is NSNull)
                #expect(Set(first.keys).isSubset(of: ["id", "trace_id", "event_type", "skill_id", "reason_code", "score", "created_at"]))
                #expect(!response.body.string.contains("client-secret"))
                #expect(!response.body.string.contains("hash-secret"))
            })

            // The dashboard resubmits the assignments it loaded on every save, including telemetry-only saves.
            let patch: [String: Any] = ["telemetry_enabled": true, "assignments": savedAssignments]
            try await app.testing().test(.PATCH, path, beforeRequest: { request in
                request.headers.replaceOrAdd(name: .cookie, value: cookie)
                request.headers.replaceOrAdd(name: .origin, value: skillUsageRouteFrontendOrigin)
                request.headers.contentType = .json
                request.body = ByteBuffer(data: try JSONSerialization.data(withJSONObject: patch))
            }, afterResponse: { response in
                #expect(response.status == .ok)
                let result = try JSONDecoder().decode(ProjectController.RuntimeSettingsResponse.self, from: Data(response.body.string.utf8))
                #expect(result.telemetry_enabled)
                #expect(result.assignments.count == 1)
                #expect(result.assignments.first?.skill_id == "review")
                #expect(result.assignments.first?.target_type == "repository")
                #expect(result.assignments.first?.target_id == "stygian/app")
                #expect(result.assignments.first?.required == true)
                #expect(result.assignments.first?.priority == 50)
            })
        }
    }
}

private let skillUsageRouteFrontendOrigin = "https://app.example.com"

private func withSkillUsageRouteApp(_ run: @Sendable @escaping (Application) async throws -> Void) async throws {
    try await TestProcessEnvGate.run {
        let keys = ["USE_MEMORY_SESSIONS", "DISABLE_SKILL_USAGE_RETENTION_SCHEDULER", "FRONTEND_URL", "CORS_ORIGIN"]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, ProcessInfo.processInfo.environment[$0]) })
        setenv("USE_MEMORY_SESSIONS", "1", 1)
        setenv("DISABLE_SKILL_USAGE_RETENTION_SCHEDULER", "1", 1)
        // Browser mutations are origin-checked; pin the frontend origin so CI and local .env agree.
        setenv("FRONTEND_URL", skillUsageRouteFrontendOrigin, 1)
        unsetenv("CORS_ORIGIN")
        defer {
            for key in keys {
                if let value = saved[key] ?? nil { setenv(key, value, 1) }
                else { unsetenv(key) }
            }
        }
        let app = try await Application.make(.testing)
        app.logger.logLevel = .warning
        do { try await configure(app); try await run(app) }
        catch { try await app.asyncShutdown(); throw error }
        try await app.asyncShutdown()
    }
}
