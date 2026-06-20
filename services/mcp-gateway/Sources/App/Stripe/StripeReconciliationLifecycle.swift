import Foundation
import Vapor

/// Periodically reconciles all Stripe subscription statuses against the Stripe API.
/// Runs 30 seconds after boot (to let the DB settle), then every 4 hours.
/// Disable with `DISABLE_STRIPE_RECONCILIATION_SCHEDULER=1`.
struct StripeReconciliationLifecycle: LifecycleHandler {
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
            application.logger.info("stripe_reconcile: scheduler disabled (DISABLE_STRIPE_RECONCILIATION_SCHEDULER)")
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
        guard let raw = Environment.get("DISABLE_STRIPE_RECONCILIATION_SCHEDULER") else { return false }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == "1" || v == "true" || v == "yes"
    }

    private static func runLoop(application: Application) async {
        // Wait briefly after boot before first run
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            return
        }

        while !Task.isCancelled {
            await StripeSubscriptionSync.reconcileAll(
                db: application.db,
                client: application.client,
                logger: application.logger,
                skipIfCheckedWithin: 3600  // don't re-check accounts the on-demand sync just touched
            )
            do {
                try await Task.sleep(for: .seconds(4 * 3600))
            } catch is CancellationError {
                break
            } catch {
                break
            }
        }
    }
}
