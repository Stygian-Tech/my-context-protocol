import Fluent
import Foundation
import Vapor

/// Runs `admin_analytics_hourly` rollup soon after boot (first deploy gets data without waiting for cron),
/// then again every hour—including Vapor `--env testing` (staging APIs). Disable with
/// `DISABLE_ADMIN_ANALYTICS_ROLLUP_SCHEDULER` (Swift CI sets this for `swift test`).
struct AdminAnalyticsRollupLifecycle: LifecycleHandler {
    private final class TaskHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var task: Task<Void, Never>?

        func replace(with newTask: Task<Void, Never>?) {
            lock.lock()
            defer { lock.unlock() }
            task?.cancel()
            task = newTask
        }

        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            task?.cancel()
            task = nil
        }
    }

    private let holder = TaskHolder()

    func didBootAsync(_ application: Application) async throws {
        guard !Self.schedulerDisabled else {
            application.logger.info("admin_analytics rollup scheduler disabled (DISABLE_ADMIN_ANALYTICS_ROLLUP_SCHEDULER)")
            return
        }
        let task = Task { @Sendable in
            await Self.runLoop(application: application)
        }
        holder.replace(with: task)
    }

    func shutdownAsync(_ application: Application) async {
        holder.cancel()
    }

    private static var schedulerDisabled: Bool {
        guard let raw = Environment.get("DISABLE_ADMIN_ANALYTICS_ROLLUP_SCHEDULER") else { return false }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == "1" || v == "true" || v == "yes"
    }

    private static func runLoop(application: Application) async {
        while !Task.isCancelled {
            do {
                try await AdminAnalyticsRollupService.refresh(
                    db: application.db,
                    logger: application.logger
                )
            } catch {
                application.logger.error(
                    "admin_analytics rollup failed: \(String(reflecting: error))"
                )
            }
            do {
                try await Task.sleep(for: .seconds(3600))
            } catch is CancellationError {
                break
            } catch {
                break
            }
        }
    }
}
