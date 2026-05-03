@testable import App
import Foundation
import Testing

struct AdminAnalyticsTimeseriesTests {
    @Test func splitsPartialHourAcrossTwoBuckets() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let half = t0.addingTimeInterval(1800)
        let full = t0.addingTimeInterval(3600)
        let buckets = [
            DashboardTimeseriesService.BucketDef(start: t0, end: half, label: "a"),
            DashboardTimeseriesService.BucketDef(start: half, end: full, label: "b"),
        ]
        let row = AdminAnalyticsHourly(
            hourStart: t0,
            requestCount: 100,
            successCount: 80,
            latencySumMs: 8000,
            latencyCount: 80,
            updatedAt: t0
        )
        let (series, updated) = AdminAnalyticsTimeseriesService.aggregateHourlyIntoBuckets(
            buckets: buckets,
            hourlyRows: [row],
            rangeEndInclusive: full
        )
        #expect(series.count == 2)
        #expect(series[0].request_count == 50)
        #expect(series[1].request_count == 50)
        #expect(series[0].success_count == 40)
        #expect(series[1].success_count == 40)
        #expect(updated == t0)
    }

    @Test func emptyRollupReturnsZeroBuckets() throws {
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        let buckets = try DashboardTimeseriesService.buildBucketDefs(
            rangeKey: "24h",
            now: end,
            earliestLog: nil
        )
        let (series, updated) = AdminAnalyticsTimeseriesService.aggregateHourlyIntoBuckets(
            buckets: buckets,
            hourlyRows: [],
            rangeEndInclusive: end
        )
        #expect(series.count == buckets.count)
        #expect(series.allSatisfy { $0.request_count == 0 })
        #expect(updated == nil)
    }
}
