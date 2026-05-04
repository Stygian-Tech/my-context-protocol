import Foundation
import Testing
@testable import App

@Suite("RequestLog client resolution")
struct RequestLogClientResolverTests {
    @Test func storedReferenceRoundTripsId() {
        let id = UUID()
        let s = RequestLogClientResolver.storedApiKeyReference(apiKeyId: id)
        #expect(s.hasPrefix(RequestLogClientResolver.apiKeyReferencePrefix))
        let ids = RequestLogClientResolver.apiKeyIds(from: [
            RequestLog(projectId: id, clientId: s, method: "x", status: "200"),
        ])
        #expect(ids == [id])
    }

    @Test func displayLabelUsesCurrentName() {
        let id = UUID()
        let pid = UUID()
        let key = ApiKey(projectId: pid, name: "Laptop", keyPrefix: "mcp_abc", keyHash: "h")
        key.id = id
        let stored = RequestLogClientResolver.storedApiKeyReference(apiKeyId: id)
        let label = RequestLogClientResolver.displayLabel(stored: stored, keysById: [id: key])
        #expect(label == "Laptop")
    }

    @Test func displayLabelFallsBackToPrefixWhenNameEmpty() {
        let id = UUID()
        let pid = UUID()
        let key = ApiKey(projectId: pid, name: nil, keyPrefix: "mcp_xyz", keyHash: "h")
        key.id = id
        let stored = RequestLogClientResolver.storedApiKeyReference(apiKeyId: id)
        let label = RequestLogClientResolver.displayLabel(stored: stored, keysById: [id: key])
        #expect(label == "mcp_xyz")
    }

    @Test func displayLabelPassesThroughOAuth() {
        let label = RequestLogClientResolver.displayLabel(stored: "oauth:pub:user", keysById: [:])
        #expect(label == "oauth:pub:user")
    }

    @Test func displayLabelRemovedKey() {
        let id = UUID()
        let stored = RequestLogClientResolver.storedApiKeyReference(apiKeyId: id)
        let label = RequestLogClientResolver.displayLabel(stored: stored, keysById: [:])
        #expect(label == "API key (removed)")
    }
}
