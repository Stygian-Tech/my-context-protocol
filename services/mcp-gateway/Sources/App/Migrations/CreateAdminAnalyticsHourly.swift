import Fluent

/// Hourly platform-wide aggregates from `request_logs` for admin dashboard charts (OLAP-friendly reads).
struct CreateAdminAnalyticsHourly: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(AdminAnalyticsHourly.schema)
            .id()
            .field("hour_start", .datetime, .required)
            .field("request_count", .int, .required)
            .field("success_count", .int, .required)
            .field("latency_sum_ms", .int, .required)
            .field("latency_count", .int, .required)
            .field("updated_at", .datetime)
            .unique(on: "hour_start")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(AdminAnalyticsHourly.schema).delete()
    }
}
