@testable import App
import Crypto
import Foundation
import NIOCore
import Testing
import Vapor
import VaporTesting

@Suite("Webhooks")
struct WebhookTests {
    @Test("POST /webhooks/github-app rejects bad HMAC")
    func githubAppBadSig() async throws {
        let prev = Environment.get("GITHUB_APP_WEBHOOK_SECRET")
        defer {
            if let prev { setenv("GITHUB_APP_WEBHOOK_SECRET", prev, 1) } else { unsetenv("GITHUB_APP_WEBHOOK_SECRET") }
        }
        setenv("GITHUB_APP_WEBHOOK_SECRET", "test_webhook_secret", 1)

        try await withApp(configure: configure) { app in
            let body = ByteBufferAllocator().buffer(string: "{}")
            try await app.testing().test(
                .POST,
                "webhooks/github-app",
                headers: [
                    "X-GitHub-Event": "installation",
                    "X-Hub-Signature-256": "sha256=deadbeef",
                    "Content-Type": "application/json",
                ],
                body: body,
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }

    @Test("POST /webhooks/github-app accepts valid HMAC for noop payload")
    func githubAppOk() async throws {
        let prev = Environment.get("GITHUB_APP_WEBHOOK_SECRET")
        defer {
            if let prev { setenv("GITHUB_APP_WEBHOOK_SECRET", prev, 1) } else { unsetenv("GITHUB_APP_WEBHOOK_SECRET") }
        }
        let secret = "test_webhook_secret"
        setenv("GITHUB_APP_WEBHOOK_SECRET", secret, 1)
        let body = #"{"action":"created","installation":{"id":1}}"#
        let bodyData = Data(body.utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: bodyData, using: SymmetricKey(data: Data(secret.utf8)))
        let sig = "sha256=" + mac.map { String(format: "%02x", $0) }.joined()

        try await withApp(configure: configure) { app in
            let buf = ByteBufferAllocator().buffer(string: body)
            try await app.testing().test(
                .POST,
                "webhooks/github-app",
                headers: [
                    "X-GitHub-Event": "installation",
                    "X-Hub-Signature-256": sig,
                    "Content-Type": "application/json",
                ],
                body: buf,
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("POST /webhooks/stripe rejects missing signature")
    func stripeMissingSig() async throws {
        let prev = Environment.get("STRIPE_WEBHOOK_SECRET")
        defer {
            if let prev { setenv("STRIPE_WEBHOOK_SECRET", prev, 1) } else { unsetenv("STRIPE_WEBHOOK_SECRET") }
        }
        setenv("STRIPE_WEBHOOK_SECRET", "stripe_test_secret", 1)

        try await withApp(configure: configure) { app in
            let body = ByteBufferAllocator().buffer(string: "{}")
            try await app.testing().test(
                .POST,
                "webhooks/stripe",
                headers: ["Content-Type": "application/json"],
                body: body,
                afterResponse: { res in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("POST /webhooks/stripe accepts valid signature")
    func stripeOk() async throws {
        let prev = Environment.get("STRIPE_WEBHOOK_SECRET")
        defer {
            if let prev { setenv("STRIPE_WEBHOOK_SECRET", prev, 1) } else { unsetenv("STRIPE_WEBHOOK_SECRET") }
        }
        let secret = "stripe_test_secret"
        setenv("STRIPE_WEBHOOK_SECRET", secret, 1)
        let payload = #"{"type":"ping","data":{}}"#
        let payloadData = Data(payload.utf8)
        let ts = String(Int(Date().timeIntervalSince1970))
        let signed = Data((ts + ".").utf8) + payloadData
        let key = StripeWebhookSignature.signingKey(from: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: signed, using: SymmetricKey(data: key))
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        let stripeSig = "t=\(ts),v1=\(hex)"

        try await withApp(configure: configure) { app in
            let buf = ByteBufferAllocator().buffer(string: payload)
            try await app.testing().test(
                .POST,
                "webhooks/stripe",
                headers: [
                    "Stripe-Signature": stripeSig,
                    "Content-Type": "application/json",
                ],
                body: buf,
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
        }
    }
}
