import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

@Suite("SyncRateLimiter")
struct SyncRateLimiterTests {
    @Test("allows up to max within window")
    func allowsBurst() {
        let limiter = SyncRateLimiter()
        let a = UUID()
        let p = UUID()
        #expect(limiter.allow(accountId: a, projectId: p, maxRequests: 3, windowSeconds: 60) == true)
        #expect(limiter.allow(accountId: a, projectId: p, maxRequests: 3, windowSeconds: 60) == true)
        #expect(limiter.allow(accountId: a, projectId: p, maxRequests: 3, windowSeconds: 60) == true)
        #expect(limiter.allow(accountId: a, projectId: p, maxRequests: 3, windowSeconds: 60) == false)
    }

    @Test("different keys are independent")
    func independentKeys() {
        let limiter = SyncRateLimiter()
        let a1 = UUID()
        let a2 = UUID()
        let p = UUID()
        #expect(limiter.allow(accountId: a1, projectId: p, maxRequests: 1, windowSeconds: 60) == true)
        #expect(limiter.allow(accountId: a1, projectId: p, maxRequests: 1, windowSeconds: 60) == false)
        #expect(limiter.allow(accountId: a2, projectId: p, maxRequests: 1, windowSeconds: 60) == true)
    }

    @Test("Application provides shared limiter")
    func applicationStorage() async throws {
        try await withApp { app in
            let x = app.syncRateLimiter
            let y = app.syncRateLimiter
            #expect(x === y)
        }
    }
}
