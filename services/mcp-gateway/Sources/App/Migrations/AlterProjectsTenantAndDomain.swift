import Fluent
import SQLKit

/// Backfills unique subdomains, replaces global slug unique with (account_id, slug), adds custom domain fields.
struct AlterProjectsTenantAndDomain: AsyncMigration {
    private let sqliteTempNewName = "projects__mcp_tenant_new"
    private let sqliteTempRevertName = "projects__mcp_tenant_revert"

    private let projectColumnOrder = [
        "id",
        "account_id",
        "name",
        "slug",
        "subdomain",
        "active_release_id",
        "created_at",
        "custom_domain",
        "custom_domain_verified_at",
        "custom_domain_verification_token",
        "mcp_catalog_markdown_override",
        "suspended_at",
    ]

    func prepare(on database: Database) async throws {
        // Idempotent: a prior crash could have added these columns before the migration row was stored.
        if let sql = database as? any SQLDatabase {
            let hasCustomDomain = try await Self.projectsTableHasColumn("custom_domain", on: sql)
            if !hasCustomDomain {
                try await database.schema("projects").field("custom_domain", .string).update()
                try await database.schema("projects").field("custom_domain_verified_at", .datetime).update()
                try await database.schema("projects").field("custom_domain_verification_token", .string).update()
            }
        } else {
            try await database.schema("projects").field("custom_domain", .string).update()
            try await database.schema("projects").field("custom_domain_verified_at", .datetime).update()
            try await database.schema("projects").field("custom_domain_verification_token", .string).update()
        }

        try await backfillSubdomains(on: database)

        if isSQLite(database) {
            guard let sql = database as? any SQLDatabase else { return }
            if try await Self.sqliteTenantSwapAlreadyApplied(on: sql) { return }
            try await prepareSwapProjectsTableForSQLite(on: database)
        } else if let sql = database as? any SQLDatabase {
            if try await Self.postgresTenantUniquesAlreadyApplied(on: sql) { return }
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
        } else {
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
    }

    func revert(on database: Database) async throws {
        if isSQLite(database) {
            try await revertSwapProjectsTableForSQLite(on: database)
        } else {
            try await database.schema("projects").deleteConstraint(name: "uq_projects_custom_domain").update()
            try await database.schema("projects").deleteConstraint(name: "uq_projects_subdomain").update()
            try await database.schema("projects").deleteConstraint(name: "uq_projects_account_slug").update()
            try await database.schema("projects").unique(on: "slug").update()
            try await database.schema("projects").deleteField("custom_domain_verification_token").update()
            try await database.schema("projects").deleteField("custom_domain_verified_at").update()
            try await database.schema("projects").deleteField("custom_domain").update()
        }
    }

    private func isSQLite(_ database: Database) -> Bool {
        guard let sql = database as? any SQLDatabase else { return false }
        return sql.dialect.name == "sqlite"
    }

    private static func projectsTableHasColumn(_ column: String, on sql: any SQLDatabase) async throws -> Bool {
        if sql.dialect.name == "sqlite" {
            return try await sql.raw(
                "SELECT 1 AS x FROM pragma_table_info('projects') WHERE name = \(bind: column) LIMIT 1"
            ).first() != nil
        }
        return try await sql.raw(
            """
            SELECT 1 AS x FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'projects' AND column_name = \(bind: column)
            LIMIT 1
            """
        ).first() != nil
    }

    /// SQLite maps inline UNIQUE constraints to `sqlite_autoindex_*`, not Fluent’s constraint names.
    /// Pre-tenant migration: one UNIQUE (`slug`). After: three UNIQUEs (account+slug, subdomain, custom_domain).
    private static func sqliteTenantSwapAlreadyApplied(on sql: any SQLDatabase) async throws -> Bool {
        let rows = try await sql.raw("PRAGMA index_list('projects')").all()
        var uniqueConstraintCount = 0
        for row in rows {
            guard let origin = try? row.decode(column: "origin", as: String.self) else { continue }
            if origin == "u" { uniqueConstraintCount += 1 }
        }
        return uniqueConstraintCount >= 3
    }

    private static func postgresTenantUniquesAlreadyApplied(on sql: any SQLDatabase) async throws -> Bool {
        try await sql.raw(
            """
            SELECT 1 AS x FROM information_schema.table_constraints
            WHERE table_schema = 'public' AND table_name = 'projects' AND constraint_name = 'uq_projects_account_slug'
            LIMIT 1
            """
        ).first() != nil
    }

    /// SQLite cannot alter uniques via Fluent; rebuild `projects` with a new table and swap.
    private func prepareSwapProjectsTableForSQLite(on database: Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }

        try await sql.raw("DROP TABLE IF EXISTS \(ident: sqliteTempNewName)").run()

        try await database.schema(sqliteTempNewName)
            .id()
            .field("account_id", .uuid, .required, .references("accounts", "id", onDelete: .cascade))
            .field("name", .string, .required)
            .field("slug", .string, .required)
            .field("subdomain", .string)
            .field("active_release_id", .uuid)
            .field("created_at", .datetime)
            .field("custom_domain", .string)
            .field("custom_domain_verified_at", .datetime)
            .field("custom_domain_verification_token", .string)
            .field("mcp_catalog_markdown_override", .string)
            .field("suspended_at", .datetime)
            .unique(on: "account_id", "slug", name: "uq_projects_account_slug")
            .unique(on: "subdomain", name: "uq_projects_subdomain")
            .unique(on: "custom_domain", name: "uq_projects_custom_domain")
            .create()

        let insertSQL: SQLQueryString = """
            INSERT INTO \(ident: sqliteTempNewName) (\(idents: projectColumnOrder, joinedBy: ","))
            SELECT \(idents: projectColumnOrder, joinedBy: ",") FROM \(ident: "projects")
            """
        try await sql.raw(insertSQL).run()

        try await sql.raw("PRAGMA foreign_keys=OFF").run()
        do {
            try await sql.raw("DROP TABLE \(ident: "projects")").run()
            try await sql.raw("ALTER TABLE \(ident: sqliteTempNewName) RENAME TO \(ident: "projects")").run()
        } catch {
            _ = try? await sql.raw("DROP TABLE IF EXISTS \(ident: sqliteTempNewName)").run()
            throw error
        }
        try await sql.raw("PRAGMA foreign_keys=ON").run()
    }

    private func revertSwapProjectsTableForSQLite(on database: Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }

        try await sql.raw("DROP TABLE IF EXISTS \(ident: sqliteTempRevertName)").run()

        try await database.schema(sqliteTempRevertName)
            .id()
            .field("account_id", .uuid, .required, .references("accounts", "id", onDelete: .cascade))
            .field("name", .string, .required)
            .field("slug", .string, .required)
            .field("subdomain", .string)
            .field("active_release_id", .uuid)
            .field("created_at", .datetime)
            .field("mcp_catalog_markdown_override", .string)
            .unique(on: "slug")
            .create()

        let revertColumns = [
            "id",
            "account_id",
            "name",
            "slug",
            "subdomain",
            "active_release_id",
            "created_at",
            "mcp_catalog_markdown_override",
        ]
        let insertSQL: SQLQueryString = """
            INSERT INTO \(ident: sqliteTempRevertName) (\(idents: revertColumns, joinedBy: ","))
            SELECT \(idents: revertColumns, joinedBy: ",") FROM \(ident: "projects")
            """
        try await sql.raw(insertSQL).run()

        try await sql.raw("PRAGMA foreign_keys=OFF").run()
        do {
            try await sql.raw("DROP TABLE \(ident: "projects")").run()
            try await sql.raw("ALTER TABLE \(ident: sqliteTempRevertName) RENAME TO \(ident: "projects")").run()
        } catch {
            _ = try? await sql.raw("DROP TABLE IF EXISTS \(ident: sqliteTempRevertName)").run()
            throw error
        }
        try await sql.raw("PRAGMA foreign_keys=ON").run()
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
