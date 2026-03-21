import Fluent

/// Backfills unique subdomains, replaces global slug unique with (account_id, slug), adds custom domain fields.
struct AlterProjectsTenantAndDomain: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("projects")
            .field("custom_domain", .string)
            .field("custom_domain_verified_at", .datetime)
            .field("custom_domain_verification_token", .string)
            .update()

        try await backfillSubdomains(on: database)

        try await database.schema("projects").deleteUnique(on: "slug").update()
        try await database.schema("projects")
            .unique(on: "account_id", "slug", name: "uq_projects_account_slug")
            .update()
        try await database.schema("projects")
            .unique(on: "subdomain", name: "uq_projects_subdomain")
            .update()
        try await database.schema("projects")
            .unique(on: "custom_domain", name: "uq_projects_custom_domain")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects").deleteConstraint(name: "uq_projects_custom_domain").update()
        try await database.schema("projects").deleteConstraint(name: "uq_projects_subdomain").update()
        try await database.schema("projects").deleteConstraint(name: "uq_projects_account_slug").update()
        try await database.schema("projects").unique(on: "slug").update()
        try await database.schema("projects").deleteField("custom_domain_verification_token").update()
        try await database.schema("projects").deleteField("custom_domain_verified_at").update()
        try await database.schema("projects").deleteField("custom_domain").update()
    }

    private func backfillSubdomains(on database: Database) async throws {
        let projects = try await Project.query(on: database).all()
        for project in projects {
            let current = project.subdomain?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard current.isEmpty else { continue }
            var candidate = TenantSubdomainGenerator.make()
            while try await Project.query(on: database).filter(\.$subdomain == candidate).first() != nil {
                candidate = TenantSubdomainGenerator.make()
            }
            project.subdomain = candidate
            try await project.save(on: database)
        }
    }
}
