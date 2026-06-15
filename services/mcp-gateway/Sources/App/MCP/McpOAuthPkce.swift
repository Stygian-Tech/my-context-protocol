import Crypto
import Foundation

enum McpOAuthPkce {
    /// Verifies PKCE S256: BASE64URL(SHA256(code_verifier)) == code_challenge
    static func verifyS256(codeVerifier: String, codeChallenge: String) -> Bool {
        let hash = SHA256.hash(data: Data(codeVerifier.utf8))
        let computed = Data(hash).base64URLEncodedString
        return constantTimeEquals(computed, codeChallenge)
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let da = Data(a.utf8)
        let db = Data(b.utf8)
        guard da.count == db.count else { return false }
        var diff: UInt8 = 0
        for i in da.indices {
            diff |= da[i] ^ db[i]
        }
        return diff == 0
    }
}
