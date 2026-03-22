@testable import App
import Testing
import VaporTesting

@Suite("App Tests")
struct AppTests {
    @Test("Health endpoint returns ok")
    func health() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "health") { res in
                #expect(res.status == .ok)
                #expect(res.body.string == "ok")
            }
        }
    }
}
