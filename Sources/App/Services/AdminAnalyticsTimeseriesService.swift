import Fluent
import Foundation
import Vapor

/// Maps hourly rollup rows into the same dashboard bucket model used by account/project charts.
enum AdminAnalyticsTimeseriesService {
    private struct Acc {
        var req: Double = 0
        var succ: Double = 0
        var latSum: Double = 0
        var latCnt: Double = 0
    }

    static func adminDashboardTimeseries(
        db: Database,
        rangeKey raw: String?,
        now: Date = Date()
    ) async throws -> AdminDashboardTimeseriesResponse {
        let rangeKey = try DashboardTimeseriesService.normalizeRangeKey(raw)
        let firstLog = try await RequestLog.query(on: db).sort(\.$timestamp, .ascending).first()
        let buckets = try DashboardTimeseriesService.buildBucketDefs(
            rangeKey: rangeKey,
            now: now,
            earliestLog: firstLog?.timestamp
        )
        let rangeStart = buckets.first?.start ?? now
        let bufferStart = buckets.first?.start.addingTimeInterval(-3600) ?? now.addingTimeInterval(-3600)
        let hourlyRows = try await AdminAnalyticsHourly.query(on: db)
            .filter(\.$hourStart >= bufferStart)
            .filter(\.$hourStart <= now)
            .sort(\.$hourStart, .ascending)
            .all()

        let (series, rollupUpdatedAt) = Self.aggregateHourlyIntoBuckets(
            buckets: buckets,
            hourlyRows: hourlyRows,
            rangeEndInclusive: now
        )

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return AdminDashboardTimeseriesResponse(
            range_key: rangeKey,
            range_start: formatter.string(from: rangeStart),
            range_end: formatter.string(from: now),
            buckets: series,
            rollup_updated_at: rollupUpdatedAt.map { formatter.string(from: $0) },
            data_source_note:
                "Charts use hourly aggregates that are refreshed periodically (target: every hour). Values may lag live traffic."
        )
    }

    /// - Returns: DTO series and latest `updated_at` seen on rollup rows in range.
    static func aggregateHourlyIntoBuckets(
        buckets: [DashboardTimeseriesService.BucketDef],
        hourlyRows: [AdminAnalyticsHourly],
        rangeEndInclusive: Date
    ) -> ([DashboardTimeseriesBucketDTO], Date?) {
        guard !buckets.isEmpty else { return ([], nil) }

        var accs = Array(repeating: Acc(), count: buckets.count)
        var maxUpdated: Date?

        for row in hourlyRows {
            if let u = row.updatedAt {
                maxUpdated = max(maxUpdated ?? u, u)
            }
            let hourStart = row.hourStart
            let hourEnd = hourStart.addingTimeInterval(3600)

            for (i, bucket) in buckets.enumerated() {
                let isLast = i == buckets.count - 1
                let bucketUpper = isLast ? rangeEndInclusive : bucket.end
                let overlapStart = max(hourStart, bucket.start)
                let overlapEnd = min(hourEnd, bucketUpper)
                if overlapEnd <= overlapStart { continue }
                let frac = overlapEnd.timeIntervalSince(overlapStart) / 3600.0
                guard frac > 0 else { continue }

                accs[i].req += Double(row.requestCount) * frac
                accs[i].succ += Double(row.successCount) * frac
                accs[i].latSum += Double(row.latencySumMs) * frac
                accs[i].latCnt += Double(row.latencyCount) * frac
            }
        }

        let series = zip(buckets, accs).map { b, a -> DashboardTimeseriesBucketDTO in
            var rc = Int(a.req.rounded())
            var sc = Int(a.succ.rounded())
            sc = min(sc, rc)
            let avg: Double? =
                a.latCnt > 0.5
                    ? a.latSum / a.latCnt
                    : nil
            return DashboardTimeseriesBucketDTO(
                label: b.label,
                start: DashboardTimeseriesService.formatISO(b.start),
                end: DashboardTimeseriesService.formatISO(b.end),
                request_count: rc,
                success_count: sc,
                avg_latency_ms: avg
            )
        }
        return (series, maxUpdated)
    }
}
