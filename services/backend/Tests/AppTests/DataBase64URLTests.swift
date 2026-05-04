import Foundation
import Testing
@testable import App

@Suite("Data base64url")
struct DataBase64URLTests {
    @Test("round-trip encodes without padding and decodes")
    func roundTrip() throws {
        let original = Data([0xFB, 0xFF, 0x01, 0x02, 0x03])
        let enc = original.base64URLEncodedString
        let dec = try #require(Data(base64URLEncoded: enc))
        #expect(dec == original)
    }

    @Test("decode round-trip preserves bytes that use URL-safe alphabet")
    func decodeUrlSafeAlphabet() throws {
        let original = Data([251, 251, 251])
        let enc = original.base64URLEncodedString
        let d = try #require(Data(base64URLEncoded: enc))
        #expect(d == original)
    }

    @Test("invalid base64 returns nil")
    func invalidNil() {
        #expect(Data(base64URLEncoded: "!!!") == nil)
    }
}
