@testable import App
import Crypto
import Foundation
import Testing

@Suite("StripeWebhookSignature")
struct StripeWebhookSignatureTests {
    @Test("signingKey uses raw bytes when not whsec_")
    func signingKeyPlain() {
        let k = StripeWebhookSignature.signingKey(from: "my_secret")
        #expect(k == Data("my_secret".utf8))
    }

    @Test("signingKey decodes whsec_ base64")
    func signingKeyWhsec() {
        let raw = Data((0 ..< 16).map { _ in UInt8(9) })
        let b64 = "whsec_" + raw.base64EncodedString()
        let k = StripeWebhookSignature.signingKey(from: b64)
        #expect(k == raw)
    }

    @Test("signingKey falls back to full secret bytes when whsec_ payload is invalid base64")
    func signingKeyWhsecInvalid() {
        let s = "whsec_!!!not-base64!!!"
        let k = StripeWebhookSignature.signingKey(from: s)
        #expect(k == Data(s.utf8))
    }

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

    @Test("rejects missing timestamp")
    func noTimestamp() throws {
        let secret = "s"
        let payload = Data("{}".utf8)
        #expect(throws: (any Error).self) {
            _ = try StripeWebhookSignature.verify(payload: payload, header: "v1=abc", secret: secret)
        }
    }

    @Test("rejects timestamp outside tolerance (too old)")
    func staleTimestamp() throws {
        let secret = "s"
        let payload = Data("{}".utf8)
        let ts = "100"
        let signed = Data((ts + ".").utf8) + payload
        let key = StripeWebhookSignature.signingKey(from: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: signed, using: SymmetricKey(data: key))
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        let header = "t=\(ts),v1=\(hex)"
        #expect(throws: (any Error).self) {
            _ = try StripeWebhookSignature.verify(payload: payload, header: header, secret: secret, toleranceSeconds: 300)
        }
    }

    @Test("rejects timestamp outside tolerance (too far in future)")
    func futureTimestamp() throws {
        let secret = "s"
        let payload = Data("{}".utf8)
        let ts = String(Int(Date().timeIntervalSince1970) + 999_999_999)
        let signed = Data((ts + ".").utf8) + payload
        let key = StripeWebhookSignature.signingKey(from: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: signed, using: SymmetricKey(data: key))
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        let header = "t=\(ts),v1=\(hex)"
        #expect(throws: (any Error).self) {
            _ = try StripeWebhookSignature.verify(payload: payload, header: header, secret: secret, toleranceSeconds: 300)
        }
    }

    @Test("accepts any matching v1 signature when multiple provided")
    func multipleV1Entries() throws {
        let secret = "sec"
        let payload = Data("x".utf8)
        let ts = String(Int(Date().timeIntervalSince1970))
        let signed = Data((ts + ".").utf8) + payload
        let key = StripeWebhookSignature.signingKey(from: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: signed, using: SymmetricKey(data: key))
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        let header = "t=\(ts),foo=bar,v1=wrong,v1=\(hex)"
        let out = try StripeWebhookSignature.verify(payload: payload, header: header, secret: secret)
        #expect(out == payload)
    }
}
