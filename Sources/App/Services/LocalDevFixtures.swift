import Fluent
import Foundation
import Vapor

/// Seeds a rich demo project + request logs when `SEED_LOCAL_FIXTURES=1` and the environment is safe for fixtures:
/// - `APP_ENV=local`, or
/// - any non-production `APP_ENV` with `USE_SQLITE=1` (file DB — avoids polluting shared Postgres).
/// Attaches to the **first** account (oldest `created_at`) — sign in with GitHub once, then restart with the env var.
enum LocalDevFixtures {
    static let showcaseSlug = "local-dev-showcase"
    static let draftSlug = "local-dev-draft"

    private static func seedFlagSet() -> Bool {
        guard let raw = Environment.get("SEED_LOCAL_FIXTURES") else { return false }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == "1" || v == "true" || v == "yes"
    }

    private static func useSqliteFileEnabled() -> Bool {
        guard let raw = Environment.get("USE_SQLITE") else { return false }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == "1" || v == "true" || v == "yes"
    }

    private static func seedEnabled() -> Bool {
        guard seedFlagSet() else { return false }
        if AppEnvironment.deployKind() == .local { return true }
        if AppEnvironment.isNonProduction, useSqliteFileEnabled() { return true }
        return false
    }

    static func seedIfNeeded(application: Application) async throws {
        let logger = application.logger

        if seedFlagSet(), !seedEnabled() {
            let env = AppEnvironment.deployKind().rawValue
            let sqlite = Environment.get("USE_SQLITE") ?? "unset"
            logger.warning(
                "SEED_LOCAL_FIXTURES is set but demo seed is disabled: use APP_ENV=local, or non-production APP_ENV with USE_SQLITE=1 (file SQLite). Current APP_ENV=\(env), USE_SQLITE=\(sqlite)."
            )
            return
        }

        guard seedEnabled() else { return }

        let db = application.db

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

    /// ~3k logs across ~400d (biased toward recent traffic) for 7d / 1mo / 3mo / 1y / “all” chart ranges.
    private static func seedRequestLogs(
        projectId: UUID,
        releaseId: UUID,
        on db: Database
    ) async throws {
        let now = Date()
        let sevenDays = 7 * 86_400
        let ninetyDays = 90 * 86_400
        let fourHundredDays = 400 * 86_400
        let midSpan = max(1, ninetyDays - sevenDays)
        let tailSpan = max(1, fourHundredDays - ninetyDays)

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

        for i in 0..<3_000 {
            let method = methodCycle[i % methodCycle.count]
            let secondsAgo: TimeInterval = {
                switch i % 10 {
                case 0 ..< 4:
                    // 40% in the last 7d — fuller 1h / 24h / 7d buckets
                    return TimeInterval((i * 1_039 + (i % 97) * 37) % sevenDays)
                case 4 ..< 8:
                    // 40% between 7d and 90d
                    return TimeInterval(sevenDays + (i * 7_919) % midSpan)
                default:
                    // 20% between 90d and 400d — Pro ranges / YTD / “all”
                    return TimeInterval(ninetyDays + (i * 104_729) % tailSpan)
                }
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
