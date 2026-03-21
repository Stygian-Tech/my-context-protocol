@testable import App
import Testing

@Suite("AppEnvironment")
struct AppEnvironmentTests {
    @Test("deploy kind and bypass flags")
    func deployAndBypass() async throws {
        let prevEnv = AppEnvironment._testOverrideAppEnv
        let prevStrict = AppEnvironment._testOverrideStrict
        defer {
            AppEnvironment._testOverrideAppEnv = prevEnv
            AppEnvironment._testOverrideStrict = prevStrict
        }

        AppEnvironment._testOverrideAppEnv = nil
        AppEnvironment._testOverrideStrict = nil
        #expect(AppEnvironment.deployKind() == .prod)
        #expect(AppEnvironment.nonProductionBypassesActive == false)

        AppEnvironment._testOverrideStrict = nil
        AppEnvironment._testOverrideAppEnv = "LOCAL"
        #expect(AppEnvironment.deployKind() == .local)
        #expect(AppEnvironment.nonProductionBypassesActive == true)

        AppEnvironment._testOverrideAppEnv = "dev"
        #expect(AppEnvironment.deployKind() == .dev)

        AppEnvironment._testOverrideAppEnv = "prod"
        #expect(AppEnvironment.deployKind() == .prod)

        AppEnvironment._testOverrideAppEnv = "local"
        AppEnvironment._testOverrideStrict = true
        #expect(AppEnvironment.strictProGating == true)
        #expect(AppEnvironment.nonProductionBypassesActive == false)
    }
}
