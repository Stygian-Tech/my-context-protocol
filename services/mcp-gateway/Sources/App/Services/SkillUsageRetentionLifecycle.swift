import Fluent
import Foundation
import Vapor

/// Prunes opted-in and inactive project histories every hour.
struct SkillUsageRetentionLifecycle: LifecycleHandler {
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
            application.logger.info("skill usage retention scheduler disabled (DISABLE_SKILL_USAGE_RETENTION_SCHEDULER)")
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
        guard let raw = Environment.get("DISABLE_SKILL_USAGE_RETENTION_SCHEDULER") else { return false }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == "1" || v == "true" || v == "yes"
    }

    private static func runLoop(application: Application) async {
        while !Task.isCancelled {
            do {
                try await SkillUsageService.prune(db: application.db)
            } catch {
                application.logger.error(
                    "skill usage retention failed: \(String(reflecting: error))"
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
