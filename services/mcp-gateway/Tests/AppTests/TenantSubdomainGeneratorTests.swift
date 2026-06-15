import Foundation
import Testing
@testable import App

@Suite("TenantSubdomainGenerator")
struct TenantSubdomainGeneratorTests {
    @Test("generates 12 lowercase alphanumeric chars")
    func shape() {
        let s = TenantSubdomainGenerator.make()
        #expect(s.count == 12)
        #expect(s == s.lowercased())
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        #expect(s.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    @Test("two samples are unlikely to collide")
    func varied() {
        let a = TenantSubdomainGenerator.make()
        let b = TenantSubdomainGenerator.make()
        #expect(a != b)
    }
}
