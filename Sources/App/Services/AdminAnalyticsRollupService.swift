import Fluent
import Foundation
import SQLKit
import Vapor

/// Refreshes `admin_analytics_hourly` from `request_logs`. Intended to run hourly (e.g. Supabase pg_cron + SQL, or `POST /admin/analytics/rollup-refresh`).
enum AdminAnalyticsRollupService {
    private static let rollupRetentionSeconds: TimeInterval = 500 * 24 * 3600

    static func refresh(db: Database, logger: Logger) async throws {
        if isSQLite(db) {
            try await refreshSQLite(db: db, logger: logger)
        } else if db is any SQLDatabase {
            try await refreshPostgres(db: db, logger: logger)
        } else {
            logger.warning("admin_analytics rollup: unknown SQL dialect, skipping refresh")
        }
    }

    private static func isSQLite(_ database: Database) -> Bool {
        guard let sql = database as? any SQLDatabase else { return false }
        return sql.dialect.name == "sqlite"
    }

    // MARK: - PostgreSQL

    private static func refreshPostgres(db: Database, logger: Logger) async throws {
        guard let sql = db as? any SQLDatabase else { return }
        // Replace recent window so hours with zero traffic drop out; keeps table small.
        try await sql.raw(
            """
            DELETE FROM admin_analytics_hourly
            WHERE hour_start >= (NOW() AT TIME ZONE 'UTC') - INTERVAL '500 days'
            """
        ).run()

        try await sql.raw(
            """
            INSERT INTO admin_analytics_hourly (id, hour_start, request_count, success_count, latency_sum_ms, latency_count, updated_at)
            SELECT gen_random_uuid(),
              agg.hour_start,
              agg.request_count,
              agg.success_count,
              agg.latency_sum_ms,
              agg.latency_count,
              NOW()
            FROM (
              SELECT
                date_trunc('hour', "timestamp" AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' AS hour_start,
                COUNT(*)::int AS request_count,
                SUM(
                  CASE
                    WHEN status ~ '^[0-9]+$' AND (CAST(status AS INTEGER) >= 200 AND CAST(status AS INTEGER) < 400)
                    THEN 1 ELSE 0
                  END
                )::int AS success_count,
                COALESCE(SUM("latency_ms"), 0)::int AS latency_sum_ms,
                COUNT("latency_ms")::int AS latency_count
              FROM request_logs
              WHERE "timestamp" >= (NOW() AT TIME ZONE 'UTC') - INTERVAL '500 days'
              GROUP BY date_trunc('hour', "timestamp" AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'
            ) AS agg
            """
        ).run()
        logger.info("admin_analytics rollup (postgres): refresh complete")
    }

    // MARK: - SQLite (tests / local file DB)

    private static func refreshSQLite(db: Database, logger: Logger) async throws {
        let now = Date()
        let cutoff = now.addingTimeInterval(-rollupRetentionSeconds)
        try await AdminAnalyticsHourly.query(on: db).filter(\.$hourStart >= cutoff).delete()

        let logs = try await RequestLog.query(on: db)
            .filter(\.$timestamp >= cutoff)
            .all()

        var bins: [Date: Bin] = [:]
        let cal = utcCalendar
        for log in logs {
            guard let ts = log.timestamp else { continue }
            let hour = cal.date(
                from: cal.dateComponents([.year, .month, .day, .hour], from: ts)
            ) ?? ts
            var b = bins[hour] ?? Bin()
            b.requestCount += 1
            if isSuccessStatus(log.status) {
                b.successCount += 1
            }
            if let lat = log.latencyMs {
                b.latencySum += lat
                b.latencyCount += 1
            }
            bins[hour] = b
        }

        for (hourStart, b) in bins {
            let row = AdminAnalyticsHourly(
                hourStart: hourStart,
                requestCount: b.requestCount,
                successCount: b.successCount,
                latencySumMs: b.latencySum,
                latencyCount: b.latencyCount,
                updatedAt: now
            )
            try await row.save(on: db)
        }
        logger.info("admin_analytics rollup (sqlite): refresh complete, \(bins.count) hour buckets")
    }

    private struct Bin {
        var requestCount = 0
        var successCount = 0
        var latencySum = 0
        var latencyCount = 0
    }

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private static func isSuccessStatus(_ status: String) -> Bool {
        guard let code = Int(status) else { return false }
        return (200 ..< 400).contains(code)
    }
}
