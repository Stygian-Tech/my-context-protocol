@testable import App
import CryptoKit
import Foundation
import Testing

@Suite("StripeWebhookSignature")
struct StripeWebhookSignatureTests {
    @Test("accepts valid signature")
    func validSig() throws {
        let secret = "test_signing_secret_plain"
        let payload = #"{"id":"evt_1"}"#.data(using: .utf8)!
        let ts = String(Int(Date().timeIntervalSince1970))
        let signed = Data((ts + ".").utf8) + payload
        let key = StripeWebhookSignature.signingKey(from: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: signed, using: SymmetricKey(data: key))
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        let header = "t=\(ts),v1=\(hex)"
        let out = try StripeWebhookSignature.verify(payload: payload, header: header, secret: secret)
        #expect(out == payload)
    }

    @Test("rejects bad signature")
    func badSig() throws {
        let secret = "test_signing_secret_plain"
        let payload = #"{"id":"evt_1"}"#.data(using: .utf8)!
        let ts = String(Int(Date().timeIntervalSince1970))
        let header = "t=\(ts),v1=deadbeef"
        #expect(throws: (any Error).self) {
            _ = try StripeWebhookSignature.verify(payload: payload, header: header, secret: secret)
        }
    }
}
