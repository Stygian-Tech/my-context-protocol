import Fluent
import Foundation
import Vapor

/// Seeds a rich demo project + request logs for **local** UI preview when `SEED_LOCAL_FIXTURES=1`.
/// Attaches to the **first** account (oldest `created_at`) — sign in with GitHub once, then restart with the env var.
enum LocalDevFixtures {
    static let showcaseSlug = "local-dev-showcase"
    static let draftSlug = "local-dev-draft"

    private static func seedEnabled() -> Bool {
        guard AppEnvironment.deployKind() == .local else { return false }
        guard let raw = Environment.get("SEED_LOCAL_FIXTURES") else { return false }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == "1" || v == "true" || v == "yes"
    }

    static func seedIfNeeded(application: Application) async throws {
        guard seedEnabled() else { return }

        let db = application.db
        let logger = application.logger

        guard let account = try await Account.query(on: db).sort(\.$createdAt, .ascending).first() else {
            logger.warning(
                "SEED_LOCAL_FIXTURES: no accounts yet. Complete GitHub sign-in once, then restart the server with SEED_LOCAL_FIXTURES=1."
            )
            return
        }
        guard let accountId = account.id else { return }

        if try await Project.query(on: db)
            .filter(\.$account.$id == accountId)
            .filter(\.$slug == showcaseSlug)
            .count() > 0 {
            logger.info(
                "SEED_LOCAL_FIXTURES: skip — project slug `\(showcaseSlug)` already exists (delete it or wipe db.sqlite to re-seed)."
            )
            return
        }

        let showcase = Project(
            accountId: accountId,
            name: "Demo MCP (local preview)",
            slug: showcaseSlug,
            subdomain: "demo-local-preview"
        )
        try await showcase.save(on: db)
        guard let projectId = showcase.id else { return }

        let draft = Project(
            accountId: accountId,
            name: "Draft project (no release)",
            slug: draftSlug,
            subdomain: "demo-local-draft"
        )
        try await draft.save(on: db)

        let connection = RepoConnection(
            projectId: projectId,
            provider: "github",
            repoOwner: "stygian-tech",
            repoName: "demo-skills-repo",
            defaultBranch: "main",
            authType: "app"
        )
        try await connection.save(on: db)

        let release = Release(
            projectId: projectId,
            commitSha: "b70b530c0ffee11eadbeef",
            status: "ready",
            skillBodyChangesCount: 1
        )
        try await release.save(on: db)
        guard let releaseId = release.id else { return }

        showcase.activeReleaseId = releaseId
        try await showcase.save(on: db)

        try await seedCatalog(releaseId: releaseId, on: db)
        try await seedRequestLogs(projectId: projectId, releaseId: releaseId, on: db)

        logger.info(
            "SEED_LOCAL_FIXTURES: seeded `\(showcaseSlug)` + `\(draftSlug)` for account `\(account.login)` (\(accountId))."
        )
    }

    private static func seedCatalog(releaseId: UUID, on db: Database) async throws {
        let packages: [(path: String, name: String, exposure: String)] = [
            ("skills/echo", "echo", "tool"),
            ("skills/guide", "demo-guide", "resource"),
            ("skills/onboarding", "onboarding", "prompt"),
        ]

        for spec in packages {
            let pkg = SkillPackage(
                releaseId: releaseId,
                path: spec.path,
                name: spec.name,
                description: "Fixture skill for local dashboard / MCP preview.",
                validationStatus: "valid"
            )
            try await pkg.save(on: db)
            guard let pkgId = pkg.id else { continue }

            let compiled = CompiledSkill(
                releaseId: releaseId,
                skillPackageId: pkgId,
                path: spec.path,
                name: spec.name,
                summary: "Local dev fixture — \(spec.name) (\(spec.exposure)).",
                skillBody: "# \(spec.name)\n\nFixture body for previews.",
                exposureType: spec.exposure,
                riskLevel: "low",
                repoSpecific: false,
                status: "ready",
                yamlFrontmatterPresent: true
            )
            try await compiled.save(on: db)
            guard let csId = compiled.id else { continue }

            let rule = RoutingRule(
                compiledSkillId: csId,
                useWhenJson: "[\"When testing the dashboard\"]",
                avoidWhenJson: "[\"Production traffic\"]",
                failureModesJson: "[\"Missing API key\"]",
                invokeFirst: spec.exposure == "tool"
            )
            try await rule.save(on: db)

            let capType = spec.exposure == "guidance" ? "prompt" : spec.exposure
            let cap = CapabilityDef(
                compiledSkillId: csId,
                capabilityName: "skill:\(spec.name)",
                type: capType,
                schemaJson: "{}",
                sideEffectLevel: "read"
            )
            try await cap.save(on: db)
        }
    }

    /// ~420 logs across 7d with MCP-like method mix, failures, and latencies for metrics + charts.
    private static func seedRequestLogs(
        projectId: UUID,
        releaseId: UUID,
        on db: Database
    ) async throws {
        let now = Date()
        let methodCycle: [String] = [
            "tools/list",
            "ping",
            "resources/list",
            "prompts/list",
            "initialize",
            "notifications/initialized",
            "resources/subscribe",
            "tools/call",
            "resources/read",
            "prompts/get",
            "notifications/cancelled",
            "resources/unsubscribe",
        ]

        for i in 0..<420 {
            let method = methodCycle[i % methodCycle.count]
            let secondsAgo: TimeInterval = {
                let r = (i * 1_039) % (7 * 86_400)
                if i % 4 == 0 { return TimeInterval(r % 86_400) }
                return TimeInterval(r)
            }()
            let ts = now.addingTimeInterval(-secondsAgo)

            var status = "200"
            var errorCode: String?
            var errorMessage: String?
            var latency = 18 + (i * 13) % 90

            if i % 29 == 0 {
                status = "401"
                errorCode = "invalid_api_key"
                errorMessage = "Invalid or revoked API key"
                latency = 2
            } else if i % 41 == 0 {
                status = "500"
                errorCode = "upstream_error"
                errorMessage = "GitHub rate limit exceeded"
                latency = 120
            }

            let log = RequestLog(
                projectId: projectId,
                releaseId: releaseId,
                clientId: i % 3 == 0 ? "cursor" : (i % 3 == 1 ? "ci" : "local-cli"),
                method: method,
                latencyMs: latency,
                status: status,
                errorCode: errorCode,
                errorMessage: errorMessage
            )
            log.timestamp = ts
            try await log.save(on: db)
        }
    }
}

struct LocalDevFixtureLifecycle: LifecycleHandler {
    func didBootAsync(_ application: Application) async throws {
        try await LocalDevFixtures.seedIfNeeded(application: application)
    }
}
