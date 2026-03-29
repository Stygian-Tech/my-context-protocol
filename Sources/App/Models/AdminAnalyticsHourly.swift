import Fluent
import Vapor

final class AdminAnalyticsHourly: Model, Content {
    static let schema = "admin_analytics_hourly"

    @ID(key: .id)
    var id: UUID?

    /// UTC start of the hour bucket (inclusive).
    @Field(key: "hour_start")
    var hourStart: Date

    @Field(key: "request_count")
    var requestCount: Int

    @Field(key: "success_count")
    var successCount: Int

    @Field(key: "latency_sum_ms")
    var latencySumMs: Int

    @Field(key: "latency_count")
    var latencyCount: Int

    @OptionalField(key: "updated_at")
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        hourStart: Date,
        requestCount: Int,
        successCount: Int,
        latencySumMs: Int,
        latencyCount: Int,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.hourStart = hourStart
        self.requestCount = requestCount
        self.successCount = successCount
        self.latencySumMs = latencySumMs
        self.latencyCount = latencyCount
        self.updatedAt = updatedAt
    }
}

extension AdminAnalyticsHourly: @unchecked Sendable {}
