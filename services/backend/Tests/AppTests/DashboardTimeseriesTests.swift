@testable import App
import Foundation
import Testing

struct DashboardTimeseriesTests {
    @Test func normalizeRangeDefaultIs24h() throws {
        let k = try DashboardTimeseriesService.normalizeRangeKey(nil)
        #expect(k == "24h")
    }

    @Test func proGating() {
        #expect(DashboardTimeseriesService.rangeRequiresPro("1h") == false)
        #expect(DashboardTimeseriesService.rangeRequiresPro("24h") == false)
        #expect(DashboardTimeseriesService.rangeRequiresPro("7d") == false)
        #expect(DashboardTimeseriesService.rangeRequiresPro("1mo") == true)
        #expect(DashboardTimeseriesService.rangeRequiresPro("ytd") == true)
        #expect(DashboardTimeseriesService.rangeRequiresPro("all") == true)
    }

    @Test func build1hHasTwelveBuckets() throws {
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        let buckets = try DashboardTimeseriesService.buildBucketDefs(
            rangeKey: "1h",
            now: end,
            earliestLog: nil
        )
        #expect(buckets.count == 12)
    }
}
