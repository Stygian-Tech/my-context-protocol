import Crypto
import Foundation
import Vapor

enum StripeWebhookSignature {
    /// Returns the HMAC key bytes for the given Stripe signing secret.
    /// Stripe uses the raw UTF-8 bytes of the full `whsec_...` string as the key.
    static func signingKey(from secret: String) -> Data {
        Data(secret.utf8)
    }

    /// Verifies `Stripe-Signature` header (t=timestamp,v1=hex,...). Returns payload if valid.
    static func verify(payload: Data, header: String, secret: String, toleranceSeconds: TimeInterval = 300) throws -> Data {
        var timestamp: String?
        var signatures: [String] = []
        for part in header.split(separator: ",") {
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { continue }
            let k = String(kv[0])
            let v = String(kv[1])
            if k == "t" {
                timestamp = v
            } else if k == "v1" {
                signatures.append(v)
            }
        }
        guard let ts = timestamp, let t = TimeInterval(ts) else {
            throw Abort(.badRequest, reason: "Invalid Stripe-Signature timestamp")
        }
        let eventTime = Date(timeIntervalSince1970: t)
        guard abs(Date().timeIntervalSince(eventTime)) <= toleranceSeconds else {
            throw Abort(.badRequest, reason: "Stripe webhook timestamp outside tolerance")
        }
        let signedPayload = Data((ts + ".").utf8) + payload
        let key = SymmetricKey(data: signingKey(from: secret))
        let mac = HMAC<SHA256>.authenticationCode(for: signedPayload, using: key)
        let expected = mac.map { String(format: "%02x", $0) }.joined()
        guard signatures.contains(expected) else {
            throw Abort(.badRequest, reason: "Invalid Stripe webhook signature")
        }
        return payload
    }
}
