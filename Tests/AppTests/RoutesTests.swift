@testable import App
import Testing
import VaporTesting

@Suite("HTTP routes")
struct RoutesTests {
    @Test("GET / returns app name")
    func root() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "/") { res in
                #expect(res.status == .ok)
                #expect(res.body.string == "MyContextProtocol")
            }
        }
    }

    @Test("GET /projects without session returns 401")
    func projectsUnauthorized() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "projects") { res in
                #expect(res.status == .unauthorized)
            }
        }
    }
}
