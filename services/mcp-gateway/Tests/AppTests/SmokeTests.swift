import Testing
@testable import App

@Suite("Smoke")
struct SmokeTests {
    @Test func appModuleLinks() {
        #expect(Bool(true))
    }
}
