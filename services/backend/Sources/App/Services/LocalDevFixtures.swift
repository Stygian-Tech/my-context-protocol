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
    /// Second fixture release: failed ingest with a rich validation report (for dashboard / dialog QA).
    static let mockErrorsCommitSha = "deadbeefcafebabe"

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

        let showcase = try await findOrCreateProject(
            accountId: accountId,
            name: "Demo MCP (local preview)",
            slug: showcaseSlug,
            subdomain: "demo-local-preview",
            on: db
        )
        guard let projectId = showcase.id else { return }

        _ = try await findOrCreateProject(
            accountId: accountId,
            name: "Draft project (no release)",
            slug: draftSlug,
            subdomain: "demo-local-draft",
            on: db
        )

        let bootstrapped = try await bootstrapShowcaseFixtureIfNeeded(showcase: showcase, on: db)
        try await ensureMockFailedValidationRelease(projectId: projectId, on: db)

        if bootstrapped {
            logger.info(
                "SEED_LOCAL_FIXTURES: seeded `\(showcaseSlug)` + `\(draftSlug)` + mock failed release for account `\(account.login)` (\(accountId))."
            )
        } else {
            logger.info(
                "SEED_LOCAL_FIXTURES: verified `\(showcaseSlug)` fixtures for account `\(account.login)` (\(accountId)); mock error release ensured."
            )
        }
    }

    private static func findOrCreateProject(
        accountId: UUID,
        name: String,
        slug: String,
        subdomain: String,
        on db: Database
    ) async throws -> Project {
        if let existing = try await Project.query(on: db)
            .filter(\.$account.$id == accountId)
            .filter(\.$slug == slug)
            .first() {
            return existing
        }
        let project = Project(
            accountId: accountId,
            name: name,
            slug: slug,
            subdomain: subdomain
        )
        try await project.save(on: db)
        return project
    }

    /// Returns `true` when this run created the demo connection / ready release / catalog / logs.
    private static func bootstrapShowcaseFixtureIfNeeded(showcase: Project, on db: Database) async throws -> Bool {
        guard let projectId = showcase.id else { return false }
        let hasConnection = try await RepoConnection.query(on: db)
            .filter(\.$project.$id == projectId)
            .count() > 0
        if hasConnection {
            return false
        }

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
        guard let releaseId = release.id else { return true }

        showcase.activeReleaseId = releaseId
        try await showcase.save(on: db)

        try await seedCatalog(releaseId: releaseId, on: db)
        try await seedRequestLogs(projectId: projectId, releaseId: releaseId, on: db)
        return true
    }

    private static func ensureMockFailedValidationRelease(projectId: UUID, on db: Database) async throws {
        if try await Release.query(on: db)
            .filter(\.$project.$id == projectId)
            .filter(\.$commitSha == mockErrorsCommitSha)
            .count() > 0 {
            return
        }

        let summaryLines = [
            "skills/broken-tool/SKILL.md: schema validation failed — `inputSchema` is not valid JSON",
            "skills/legacy-resource/SKILL.md: exposure `resource` requires `use_when` in front matter (missing)",
            "ingest: duplicate capability name `echo` from skills/extra/echo/SKILL.md (conflicts with skills/echo)",
            "skills/leaky-prompt/SKILL.md: risk_level `high` is not allowed for prompts on the starter plan",
        ].joined(separator: "\n")

        let release = Release(
            projectId: projectId,
            commitSha: mockErrorsCommitSha,
            status: "failed",
            errorSummary: summaryLines,
            skillBodyChangesCount: 0
        )
        try await release.save(on: db)
        guard let releaseId = release.id else { return }

        let errors: [[String: Any]] = [
            [
                "path": "skills/broken-tool/SKILL.md",
                "code": "invalid_json_schema",
                "line": 14,
                "summary": "Tool inputSchema is invalid JSON",
                "fix_hint":
                    "Close the trailing brace on the `properties` object or paste the block into `jq` to find the first syntax error.",
                "message":
                    "Tool inputSchema is invalid JSON — parser stopped near the `required` array (unclosed string).",
            ],
            [
                "path": "skills/legacy-resource/SKILL.md",
                "code": "resource_use_when_required",
                "line": 3,
                "summary": "Resource exposure requires `use_when`",
                "fix_hint":
                    "Add a `use_when` list in YAML front matter (e.g. `[\"When the user asks for legacy docs\"]`).",
                "message": "Resource exposure requires `use_when` in front matter (missing).",
            ],
            [
                "path": "skills/extra/echo/SKILL.md",
                "code": "duplicate_capability",
                "line": 1,
                "summary": "Duplicate MCP tool name `echo`",
                "fix_hint":
                    "Rename this package folder or change `name` in front matter so it does not collide with `skills/echo`.",
                "message":
                    "Duplicate capability name `echo` from skills/extra/echo/SKILL.md (conflicts with skills/echo).",
            ],
            [
                "path": "skills/leaky-prompt/SKILL.md",
                "code": "risk_tier_blocked",
                "line": 22,
                "summary": "High-risk prompt blocked for workspace tier",
                "fix_hint": "Lower `risk_level` to `medium` or upgrade the project; see workspace policy docs.",
                "message":
                    "risk_level `high` is not allowed for prompts on the starter plan — downgrade or request an upgrade.",
            ],
            [
                "path": "ingest/bundle",
                "code": "bundle_checksum_mismatch",
                "summary": "Downloaded tarball did not match advertised digest",
                "fix_hint": "Re-run sync; if it persists, revoke the GitHub App cache key and reconnect the repository.",
                "message":
                    "Bundle checksum mismatch (expected sha256:aa…ff, got sha256:bb…11). Sync aborted before compile.",
            ],
        ]

        let warnings: [[String: Any]] = [
            [
                "path": "skills/quiet-helper/SKILL.md",
                "code": "no_yaml_frontmatter",
                "line": 1,
                "summary": "No YAML front matter block",
                "fix_hint":
                    "Add a `---` … `---` block with at least `name` and `description`, or move the file under a folder named after the skill.",
                "message":
                    "Skill ingested from path only; YAML front matter was missing — MCP name was inferred from the directory.",
            ],
            [
                "path": "skills/guide/SKILL.md",
                "code": "description_truncated",
                "line": 6,
                "summary": "Description exceeded 280 characters",
                "fix_hint": "Shorten the `description` field; long prose belongs in the markdown body.",
                "message": "Description was truncated to 280 characters for the MCP catalog listing.",
            ],
        ]

        let payload: [String: Any] = [
            "is_valid": false,
            "errors": errors,
            "warnings": warnings,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let reportJson = String(data: data, encoding: .utf8) ?? "{}"
        let record = ValidationReportRecord(releaseId: releaseId, reportJson: reportJson)
        try await record.save(on: db)
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
                capabilityName: MCPConstants.compiledCapabilityWireName(skillSlug: spec.name),
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
