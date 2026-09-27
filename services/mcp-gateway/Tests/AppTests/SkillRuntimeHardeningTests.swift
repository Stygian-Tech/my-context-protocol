import Foundation
import Fluent
import Testing
import Vapor
import VaporTesting
import Yams
@testable import App

@Suite("Portable skill runtime hardening", .serialized)
struct SkillRuntimeHardeningTests {
    @Test("Standard validation enforces folder identity, description, slug, and reserved names")
    func standardValidationMatrix() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skill-validation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func report(folder: String, name: String, description: String?) throws -> ValidationReport {
            let directory = root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var lines = ["---", "name: \(name)"]
            if let description { lines.append("description: \(description)") }
            lines.append(contentsOf: ["kind: task", "scope: task", "---", "Body"])
            let file = directory.appendingPathComponent("SKILL.md")
            try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            return Validator.validate(try SkillParser.parse(fileURL: file, basePath: root.path))
        }

        #expect(try report(folder: "valid-skill", name: "valid-skill", description: "Valid description").isValid)
        #expect(try !report(folder: "different-folder", name: "different-name", description: "Valid description").isValid)
        #expect(try !report(folder: "double--hyphen", name: "double--hyphen", description: "Valid description").isValid)
        #expect(try !report(folder: "trailing-", name: "trailing-", description: "Valid description").isValid)
        #expect(try !report(folder: "missing-description", name: "missing-description", description: nil).isValid)
        #expect(try !report(folder: "long-description", name: "long-description", description: String(repeating: "a", count: 1025)).isValid)
        #expect(try !report(folder: "resolve_context", name: "resolve_context", description: "Reserved").isValid)
        #expect(try !report(folder: "mycontext_catalog", name: "mycontext_catalog", description: "Reserved alias").isValid)
    }

    @Test("Duplicate skill IDs are rejected within one release")
    func duplicateIDs() throws {
        let rootA = FileManager.default.temporaryDirectory.appendingPathComponent("duplicate-a-\(UUID().uuidString)/same-skill")
        let rootB = FileManager.default.temporaryDirectory.appendingPathComponent("duplicate-b-\(UUID().uuidString)/same-skill")
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootA.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: rootB.deletingLastPathComponent())
        }
        let contents = "---\nname: same-skill\ndescription: Same identifier\n---\nBody"
        let fileA = rootA.appendingPathComponent("SKILL.md")
        let fileB = rootB.appendingPathComponent("SKILL.md")
        try contents.write(to: fileA, atomically: true, encoding: .utf8)
        try contents.write(to: fileB, atomically: true, encoding: .utf8)
        let first = try SkillParser.parse(fileURL: fileA, basePath: rootA.deletingLastPathComponent().path)
        let second = try SkillParser.parse(fileURL: fileB, basePath: rootB.deletingLastPathComponent().path)
        let errors = Validator.duplicateSkillIDErrors([first, second])
        #expect(errors.count == 2)
        #expect(errors.allSatisfy { $0.message.contains("duplicate skill id") })
    }

    @Test("Standard Agent Skills receive deterministic safe defaults")
    func standardDefaults() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("standard-skill-\(UUID().uuidString)")
        let directory = root.appendingPathComponent("review-code")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = directory.appendingPathComponent("SKILL.md")
        try """
        ---
        name: review-code
        description: Review a change for correctness.
        license: Apache-2.0
        compatibility: Requires git.
        metadata:
          owner: platform
        allowed-tools: Read Grep
        ---
        Review the requested change.
        """.write(to: file, atomically: true, encoding: .utf8)

        let parsed = try SkillParser.parse(fileURL: file, basePath: root.path)
        let package = SkillPackage(releaseId: UUID(), path: parsed.path, name: parsed.name)
        let result = SkillCanonicalCompiler.compile(
            parsed: parsed,
            package: package,
            repository: "example/skills",
            revision: "abc123"
        )

        #expect(result.questions.isEmpty)
        #expect(!result.document.validation.clarificationRequired)
        #expect(result.document.kind == .task)
        #expect(result.document.scope == .task)
        #expect(result.document.activation.mode == .intent)
        #expect(result.document.enforcement == .advisory)
        #expect(result.document.priority == 50)
        #expect(result.document.version == "abc123+\(parsed.hash!.prefix(12))")
        #expect(result.document.standardFrontmatterJson?.contains("Apache-2.0") == true)
        #expect(Compiler.exposureType(for: parsed) == "resource")
    }

    @Test("Source policy sidecar is parsed without touching SKILL markdown")
    func sidecarPolicy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skill-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".mycontext"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        version: 1
        skills:
          review-code:
            base_checksum: deadbeef
            metadata:
              exposure: resource
              scope: repository
              priority: 75
              avoid_when: [frontend only]
              activation:
                mode: intent
                intents: [review code]
                events: []
                tags: [review]
                examples: [Review this pull request]
              requires:
                - capability: repository.read
                  required: true
                  on_missing: fail_activation
              conflicts_with: [write-without-review]
        """.write(to: root.appendingPathComponent(".mycontext/skills.yaml"), atomically: true, encoding: .utf8)

        let policies = try SkillCanonicalCompiler.sourcePolicies(repoRoot: root)
        #expect(policies["review-code"]?.policy.baseChecksum == "deadbeef")
        #expect(policies["review-code"]?.policy.metadata.scope == .repository)
        #expect(policies["review-code"]?.policy.metadata.priority == 75)
        #expect(policies["review-code"]?.policy.metadata.exposure == "resource")
        #expect(policies["review-code"]?.policy.metadata.avoidWhen == ["frontend only"])
        #expect(policies["review-code"]?.policy.metadata.activation?.examples == ["Review this pull request"])
        #expect(policies["review-code"]?.policy.metadata.requires?.first?.onMissing == .failActivation)
        #expect(policies["review-code"]?.policy.metadata.conflictsWith == ["write-without-review"])
    }

    @Test("Configured central skill repository compiles all six packages without assignments")
    func centralSkillRepositoryCompatibility() throws {
        guard let path = ProcessInfo.processInfo.environment["CENTRAL_SKILLS_REPO"], !path.isEmpty else {
            return
        }
        let root = URL(fileURLWithPath: path).standardizedFileURL
        let policies = try SkillCanonicalCompiler.sourcePolicies(repoRoot: root)
        let skillFiles = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).compactMap { directory -> URL? in
            let candidate = directory.appendingPathComponent("SKILL.md")
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }.sorted { $0.path < $1.path }
        #expect(skillFiles.count == 6)
        #expect(policies.count == 6)

        for file in skillFiles {
            let parsed = try SkillParser.parse(fileURL: file, basePath: root.path)
            let validation = Validator.validate(parsed)
            #expect(validation.isValid, "\(parsed.path): \(validation.errors.map(\.message).joined(separator: "; "))")
            let package = SkillPackage(releaseId: UUID(), path: parsed.path, name: parsed.name)
            let result = SkillCanonicalCompiler.compile(
                parsed: parsed,
                package: package,
                repository: "countablenewt/skills",
                revision: "central-test",
                sourcePolicy: policies[parsed.name]?.policy
            )
            #expect(!result.document.validation.clarificationRequired)
            #expect(result.document.activation.mode != .explicit)
            #expect(Compiler.exposureType(
                for: parsed,
                policyExposure: policies[parsed.name]?.policy.metadata.exposure
            ) == "resource")
        }
    }

    @Test("Source policy sidecar rejects invalid structure and runtime values")
    func invalidSidecarPolicyFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-skill-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".mycontext"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(".mycontext/skills.yaml")

        func failure(for yaml: String) throws -> String {
            try yaml.write(to: file, atomically: true, encoding: .utf8)
            do {
                _ = try SkillCanonicalCompiler.sourcePolicies(repoRoot: root)
                return ""
            } catch {
                return error.localizedDescription
            }
        }

        #expect(try failure(for: "skills: {}\n").contains("version is required"))
        #expect(try failure(for: "version: 2\nskills: {}\n").contains("version 2 is unsupported"))
        #expect(try failure(for: "version: 1\nskills: []\n").contains("skills is required and must be a mapping"))
        #expect(try failure(for: "version: 1\nskills:\n  review-code: value\n").contains("skills.review-code"))
        #expect(try failure(for: "version: 1\nskills:\n  review-code:\n    metadata:\n      scope: repositorry\n").contains("skills.review-code"))
        #expect(try failure(for: "version: 1\nskills:\n  review-code:\n    metadata:\n      activation:\n        mode: sometimes\n").contains("skills.review-code"))
        #expect(try failure(for: "version: 1\nskills:\n  review-code:\n    metadata:\n      exposure: guidance\n").contains("metadata.exposure"))
        #expect(try failure(for: "version: 1\nskills:\n  review-code:\n    metadata:\n      priority: 101\n").contains("metadata.priority"))
    }

    @Test("Override selection is repository-aware and deterministic")
    func deterministicOverrideSelection() throws {
        let currentRepository = UUID()
        let otherRepository = UUID()

        func override(scope: SkillScope, repository: UUID?, updatedAt: Date) -> SkillRuntimeOverride {
            let row = SkillRuntimeOverride()
            row.id = UUID()
            row.skillId = "review-code"
            row.scope = scope.rawValue
            row.metadataJson = "{}"
            row.sourceChecksum = nil
            row.baseChecksum = nil
            row.isStale = false
            row.$repoConnection.id = repository
            row.updatedAt = updatedAt
            return row
        }

        let projectFallback = override(scope: .repository, repository: nil, updatedAt: Date(timeIntervalSince1970: 300))
        let currentRepo = override(scope: .repository, repository: currentRepository, updatedAt: Date(timeIntervalSince1970: 100))
        let otherRepo = override(scope: .task, repository: otherRepository, updatedAt: Date(timeIntervalSince1970: 400))
        let currentTask = override(scope: .task, repository: currentRepository, updatedAt: Date(timeIntervalSince1970: 200))

        let selected = Compiler.selectOverride(
            from: [projectFallback, currentTask, otherRepo, currentRepo],
            repoConnectionId: currentRepository,
            preferredScope: .repository
        )
        #expect(selected?.id == currentRepo.id)

        let projectSelected = Compiler.selectOverride(
            from: [otherRepo, projectFallback],
            repoConnectionId: nil,
            preferredScope: .repository
        )
        #expect(projectSelected?.id == projectFallback.id)
    }

    @Test("Writeback merges the sidecar and never reconstructs SKILL markdown")
    func writebackSidecarMerge() throws {
        let document = CompiledSkillDocument(
            schemaVersion: 1,
            id: "review-code",
            name: "review-code",
            description: "Review code",
            kind: .task,
            scope: .repository,
            activation: .init(mode: .intent, intents: ["review"], events: [], tags: [], examples: []),
            enforcement: .advisory,
            priority: 50,
            requires: [],
            conflictsWith: [],
            instructions: "# Authored body\nDo not rewrite me.",
            source: .init(repository: "example/skills", path: "review-code/SKILL.md", revision: "abc", checksum: "checksum"),
            version: "abc+checksum",
            lifecycle: nil,
            validation: .init(clarificationRequired: false, missingFields: [], warnings: [])
        )
        let merged = try SkillMetadataWritebackService.mergedSidecar(
            existing: "version: 1\nskills:\n  other-skill:\n    base_checksum: other\n    metadata:\n      priority: 10\n  review-code:\n    extension_key: keep-me\n    metadata:\n      provider_extension: preserved\n      priority: 1\n",
            document: document
        )
        let root = try load(yaml: merged) as? [String: Any]
        let skills = root?["skills"] as? [String: Any]
        let review = skills?["review-code"] as? [String: Any]
        let metadata = review?["metadata"] as? [String: Any]
        #expect(skills?["other-skill"] != nil)
        #expect(review?["extension_key"] as? String == "keep-me")
        #expect(metadata?["provider_extension"] as? String == "preserved")
        #expect(metadata?["priority"] as? Int == 50)
        #expect(!merged.contains("Authored body"))
        #expect(!merged.contains("Do not rewrite me"))
    }

    @Test("Resolver applies negative hints, assignment activation, and capability fallback deterministically")
    func deterministicResolverRules() {
        #expect(SkillRuntimeResolver.avoidMatch(["frontend only"], tokens: ["frontend", "only", "layout"]))
        #expect(!SkillRuntimeResolver.avoidMatch(["frontend only"], tokens: ["backend", "layout"]))
        #expect(SkillRuntimeResolver.activationMatches("always", isCurrent: false, eventMatch: false, intentMatch: false))
        #expect(SkillRuntimeResolver.activationMatches("event", isCurrent: false, eventMatch: true, intentMatch: false))
        #expect(!SkillRuntimeResolver.activationMatches("event", isCurrent: false, eventMatch: false, intentMatch: true))
        #expect(SkillRuntimeResolver.activationMatches("intent", isCurrent: false, eventMatch: false, intentMatch: true))
        #expect(!SkillRuntimeResolver.activationMatches("intent", isCurrent: false, eventMatch: true, intentMatch: false))
        #expect(!SkillRuntimeResolver.activationMatches("explicit", isCurrent: false, eventMatch: true, intentMatch: true))
        #expect(SkillRuntimeResolver.activationMatches("explicit", isCurrent: true, eventMatch: false, intentMatch: false))
        #expect(SkillRuntimeResolver.scopeHasContext(.global, context: .init()))
        #expect(!SkillRuntimeResolver.scopeHasContext(.repository, context: .init()))
        #expect(SkillRuntimeResolver.scopeHasContext(
            .repository,
            context: .init(repository: "Stygian-Tech/my-context-protocol")
        ))

        let binding = SkillRuntimeResolver.bind(
            .init(capability: "issue.create", required: true, onMissing: .failActivation),
            tools: []
        )
        #expect(binding.missing)
        #expect(binding.fallback == "fail_activation")
    }

    @Test("Package support files are persisted with bounded relative paths and checksums")
    func packageFilePersistence() async throws {
        try await TestProcessEnvGate.run {
            let keys = ["USE_SQLITE", "USE_MEMORY_SESSIONS", "DATABASE_URL", "SUPABASE_DB_URL"]
            let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, ProcessInfo.processInfo.environment[$0]) })
            setenv("USE_SQLITE", "1", 1)
            setenv("USE_MEMORY_SESSIONS", "1", 1)
            unsetenv("DATABASE_URL")
            unsetenv("SUPABASE_DB_URL")
            defer {
                for key in keys {
                    if let value = saved[key] ?? nil { setenv(key, value, 1) } else { unsetenv(key) }
                }
            }
            let app = try await Application.make(.testing)
            do {
            try await configure(app)
            let account = Account(githubId: 939_001, login: "package-files", email: "package-files@example.com")
            try await account.save(on: app.db)
            let project = Project(accountId: account.id!, name: "Package files", slug: "package-files", subdomain: "packagefiles")
            try await project.save(on: app.db)
            let release = Release(projectId: project.id!, commitSha: "abc", status: "pending")
            try await release.save(on: app.db)
            let package = SkillPackage(releaseId: release.id!, path: "review/SKILL.md", name: "review")
            try await package.save(on: app.db)

            let root = FileManager.default.temporaryDirectory.appendingPathComponent("package-files-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root.appendingPathComponent("references"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try "# Skill".write(to: root.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            try "Reference material".write(to: root.appendingPathComponent("references/guide.md"), atomically: true, encoding: .utf8)

            try await SyncPipeline.persistPackageFiles(package: package, skillDirectory: root, db: app.db)
            let rows = try await SkillPackageFile.query(on: app.db).all()
            #expect(rows.count == 1)
            #expect(rows[0].path == "references/guide.md")
            #expect(rows[0].byteCount == Data("Reference material".utf8).count)
            #expect(rows[0].checksum.count == 64)
            #expect(rows[0].contentType == "text/markdown")

            #expect(throws: PackageFileIngestionError.unsafeEntry) {
                _ = try SyncPipeline.safePackageRelativePath(
                    fileURL: root.deletingLastPathComponent().appendingPathComponent("outside.txt"),
                    root: root
                )
            }

            let symlinkRoot = FileManager.default.temporaryDirectory.appendingPathComponent("package-symlink-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: symlinkRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: symlinkRoot) }
            let outside = symlinkRoot.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).txt")
            try "outside".write(to: outside, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: outside) }
            try FileManager.default.createSymbolicLink(at: symlinkRoot.appendingPathComponent("linked.txt"), withDestinationURL: outside)
            let symlinkPackage = SkillPackage(releaseId: release.id!, path: "symlink/SKILL.md", name: "symlink")
            try await symlinkPackage.save(on: app.db)
            await #expect(throws: PackageFileIngestionError.unsafeEntry) {
                try await SyncPipeline.persistPackageFiles(package: symlinkPackage, skillDirectory: symlinkRoot, db: app.db)
            }

            let countRoot = FileManager.default.temporaryDirectory.appendingPathComponent("package-count-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: countRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: countRoot) }
            for index in 0...SyncPipeline.maxPackageFileCount {
                FileManager.default.createFile(atPath: countRoot.appendingPathComponent("\(index).txt").path, contents: Data())
            }
            let countPackage = SkillPackage(releaseId: release.id!, path: "count/SKILL.md", name: "count")
            try await countPackage.save(on: app.db)
            await #expect(throws: PackageFileIngestionError.boundsExceeded) {
                try await SyncPipeline.persistPackageFiles(package: countPackage, skillDirectory: countRoot, db: app.db)
            }
            let partialCount = try await SkillPackageFile.query(on: app.db)
                .filter(\.$skillPackage.$id == countPackage.id!)
                .count()
            #expect(partialCount == 0)

            let nestedRoot = FileManager.default.temporaryDirectory.appendingPathComponent("package-nested-\(UUID().uuidString)")
            let childRoot = nestedRoot.appendingPathComponent("child")
            try FileManager.default.createDirectory(at: childRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: nestedRoot) }
            try "Parent reference".write(to: nestedRoot.appendingPathComponent("parent.txt"), atomically: true, encoding: .utf8)
            try "---\nname: child\ndescription: Child skill\n---\nChild".write(
                to: childRoot.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
            )
            try "Child secret".write(to: childRoot.appendingPathComponent("child.txt"), atomically: true, encoding: .utf8)
            let nestedPackage = SkillPackage(releaseId: release.id!, path: "parent/SKILL.md", name: "parent")
            try await nestedPackage.save(on: app.db)
            try await SyncPipeline.persistPackageFiles(package: nestedPackage, skillDirectory: nestedRoot, db: app.db)
            let nestedPaths = try await SkillPackageFile.query(on: app.db)
                .filter(\.$skillPackage.$id == nestedPackage.id!)
                .all()
                .map(\.path)
            #expect(nestedPaths == ["parent.txt"])

            let sizeRoot = FileManager.default.temporaryDirectory.appendingPathComponent("package-size-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: sizeRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: sizeRoot) }
            try Data(repeating: 0x61, count: SyncPipeline.maxPackageFileBytes + 1)
                .write(to: sizeRoot.appendingPathComponent("oversized.bin"))
            let sizePackage = SkillPackage(releaseId: release.id!, path: "size/SKILL.md", name: "size")
            try await sizePackage.save(on: app.db)
            await #expect(throws: PackageFileIngestionError.boundsExceeded) {
                try await SyncPipeline.persistPackageFiles(package: sizePackage, skillDirectory: sizeRoot, db: app.db)
            }
            } catch {
                try await app.asyncShutdown()
                throw error
            }
            try await app.asyncShutdown()
        }
    }
}
