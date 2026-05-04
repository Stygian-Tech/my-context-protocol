import Foundation

/// Serializes test bodies that mutate the libc / `ProcessInfo` environment (`setenv` / `unsetenv`)
/// so parallel Swift Testing workers do not clobber each other's `Environment.get` reads.
///
/// **Why not an actor?** When an actor method `await`s, another task can enter the actor while the
/// first is suspended, so two tests could interleave env mutations.
///
/// **Why not `NSLock`?** Swift 6 forbids `NSLock` in `async` functions; this async lane serializes
/// the full `await` region instead.
///
/// **Nested `run` / `runSync`:** Do not nest calls; the lane is non-reentrant (same as a mutex).
enum TestProcessEnvGate {
    private static let lane = AsyncOneLane()

    /// Holds exclusive access for the entire async region, including awaits.
    static func run<R: Sendable>(_ body: @Sendable () async throws -> R) async rethrows -> R {
        await lane.enter()
        do {
            let result = try await body()
            await lane.leave()
            return result
        } catch {
            await lane.leave()
            throw error
        }
    }

    static func run<R: Sendable>(_ body: @Sendable () async -> R) async -> R {
        await lane.enter()
        let result = await body()
        await lane.leave()
        return result
    }

    static func runSync<R: Sendable>(_ body: @Sendable () throws -> R) rethrows -> R {
        enterSync()
        defer { leaveSync() }
        return try body()
    }

    static func runSync<R: Sendable>(_ body: @Sendable () -> R) -> R {
        enterSync()
        defer { leaveSync() }
        return body()
    }

    private static func enterSync() {
        let entered = DispatchSemaphore(value: 0)
        Task {
            await lane.enter()
            entered.signal()
        }
        entered.wait()
    }

    private static func leaveSync() {
        let left = DispatchSemaphore(value: 0)
        Task {
            await lane.leave()
            left.signal()
        }
        left.wait()
    }
}

/// Exclusive async “mutex”: one waiter at a time from entry until `leave()` (including across awaits).
private actor AsyncOneLane {
    private var taken = false
    private var queue: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if !taken {
            taken = true
            return
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.append(c)
        }
    }

    func leave() {
        if queue.isEmpty {
            taken = false
        } else {
            let next = queue.removeFirst()
            next.resume()
        }
    }
}
