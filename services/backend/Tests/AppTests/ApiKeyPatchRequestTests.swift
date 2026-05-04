@testable import App
import Testing
import Vapor

@Suite("API key patch request")
struct ApiKeyPatchRequestTests {
    @Test("Trims surrounding whitespace")
    func trimsName() throws {
        let request = ApiKeyPatchRequest(name: "  Production Cursor  ")
        #expect(try request.normalizedName() == "Production Cursor")
    }

    @Test("Whitespace-only names become nil")
    func emptyNameBecomesNil() throws {
        let request = ApiKeyPatchRequest(name: "   ")
        #expect(try request.normalizedName() == nil)
    }

    @Test("Rejects names longer than 64 characters")
    func rejectsTooLongName() throws {
        let request = ApiKeyPatchRequest(name: String(repeating: "a", count: 65))
        do {
            _ = try request.normalizedName()
            Issue.record("Expected overly long API key names to throw")
        } catch let error as Abort {
            #expect(error.status == .badRequest)
        }
    }
}
