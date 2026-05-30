import Fluent

struct CreateValidationReports: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("validation_reports")
            .id()
            .field("release_id", .uuid, .required, .references("releases", "id", onDelete: .cascade))
            .field("report_json", .string, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("validation_reports").delete()
    }
}
