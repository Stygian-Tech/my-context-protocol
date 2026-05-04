import Crypto
import Foundation
import Testing
import Vapor
@testable import App

@Suite("Security hardening")
struct SecurityHardeningTests {
    @Test("GitHub webhook HMAC accepts valid signature")
    func githubHmacValid() {
        let secret = "secret"
        let body = Data("payload".utf8)
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: body, using: key)
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        let header = "sha256=\(hex)"
        #expect(GitHubWebhookHMAC.isValid(signatureHeader: header, body: body, secret: secret))
    }

    @Test("GitHub webhook HMAC rejects tampered body")
    func githubHmacInvalid() {
        let secret = "secret"
        let body = Data("payload".utf8)
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data("other".utf8), using: key)
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        let header = "sha256=\(hex)"
        #expect(!GitHubWebhookHMAC.isValid(signatureHeader: header, body: body, secret: secret))
    }

    @Test("Relative browser path rejects open redirect patterns")
    func relativePathValidation() throws {
        #expect(throws: Abort.self) {
            try AppFrontendURL.validateRelativeBrowserPath("//evil", label: "t")
        }
        let ok = try AppFrontendURL.validateRelativeBrowserPath("/dashboard?a=1", label: "t")
        #expect(ok == "/dashboard?a=1")
    }

    @Test("Checkout path validation")
    func checkoutPaths() throws {
        let d = try AppFrontendURL.validateCheckoutRelativePath(nil, default: "/?billing=success")
        #expect(d == "/?billing=success")
        #expect(throws: Abort.self) {
            try AppFrontendURL.validateCheckoutRelativePath("//x", default: "/")
        }
    }

    @Test("GitHub webhook HMAC rejects wrong prefix and malformed hex")
    func githubHmacMalformed() {
        let secret = "secret"
        let body = Data("payload".utf8)
        #expect(!GitHubWebhookHMAC.isValid(signatureHeader: "sha1=abcdef", body: body, secret: secret))
        #expect(!GitHubWebhookHMAC.isValid(signatureHeader: "sha256=gg", body: body, secret: secret))
        #expect(!GitHubWebhookHMAC.isValid(signatureHeader: "sha256=a", body: body, secret: secret))
        #expect(!GitHubWebhookHMAC.isValid(signatureHeader: "sha256=", body: body, secret: secret))
    }

    @Test("GitHub webhook HMAC rejects wrong secret")
    func githubHmacWrongSecret() {
        let body = Data("x".utf8)
        let key = SymmetricKey(data: Data("right".utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: body, using: key)
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        #expect(!GitHubWebhookHMAC.isValid(signatureHeader: "sha256=\(hex)", body: body, secret: "wrong"))
    }

    @Test("Relative path rejects newline, nul, length, missing slash")
    func relativePathMore() throws {
        #expect(throws: Abort.self) {
            try AppFrontendURL.validateRelativeBrowserPath("/x\ny", label: "t")
        }
        #expect(throws: Abort.self) {
            try AppFrontendURL.validateRelativeBrowserPath("/x\0", label: "t")
        }
        #expect(throws: Abort.self) {
            try AppFrontendURL.validateRelativeBrowserPath("relative-only", label: "t")
        }
        let ok = try AppFrontendURL.validateRelativeBrowserPath("  /trimmed  ", label: "t")
        #expect(ok == "/trimmed")
    }
}
