@testable import App
import Testing
import Vapor

@Suite("API key create request")
struct ApiKeyCreateRequestTests {
    @Test("Trims surrounding whitespace")
    func trimsName() throws {
        let request = ApiKeyCreateRequest(name: "  Production Cursor  ")

        #expect(try request.normalizedName() == "Production Cursor")
    }

    @Test("Empty names become nil")
    func emptyNameBecomesNil() throws {
        let request = ApiKeyCreateRequest(name: "   ")

        #expect(try request.normalizedName() == nil)
    }

    @Test("Rejects names longer than 64 characters")
    func rejectsTooLongName() throws {
        let request = ApiKeyCreateRequest(name: String(repeating: "a", count: 65))

        do {
            _ = try request.normalizedName()
            Issue.record("Expected overly long API key names to throw")
        } catch let error as Abort {
            #expect(error.status == .badRequest)
        }
    }
}
