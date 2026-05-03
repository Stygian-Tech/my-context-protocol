import Crypto
import Foundation
import Vapor

/// HMAC-signed OAuth `state` so `return_to` (and GitHub App install context) survives without server session
/// (fixes multi-instance / memory session loss on callback).
enum SignedOAuthState {
    enum StateError: Error {
        case keyNotConfigured
        case invalidFormat
        case signatureMismatch
        case expired
        case invalidPayloadKind
    }

    private static let oauthKind = "gh_oauth_v1"
    private static let appKind = "gh_app_v1"

    private struct GitHubOAuthPayload: Codable {
        let k: String
        let rt: String
        let exp: Int64
        let n: String
    }

    private struct GitHubAppPayload: Codable {
        let k: String
        let pid: String
        let rt: String?
        /// Target repo the user is connecting (optional; used to resume the connect form after install).
        let owner: String?
        let repo: String?
        let exp: Int64
        let n: String
    }

    private static func hmacKey() throws -> SymmetricKey {
        guard let keyBase64 = Environment.get("ENCRYPTION_KEY"), !keyBase64.isEmpty,
              let keyData = Data(base64Encoded: keyBase64), keyData.count == 32 else {
            throw StateError.keyNotConfigured
        }
        return SymmetricKey(data: keyData)
    }

    private static func signPayload(_ json: Data, key: SymmetricKey) throws -> String {
        let sig = Data(HMAC<SHA256>.authenticationCode(for: json, using: key))
        return json.base64URLEncodedString + "." + sig.base64URLEncodedString
    }

    private static func verifyAndDecode(_ state: String, key: SymmetricKey) throws -> Data {
        let parts = state.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let json = Data(base64URLEncoded: String(parts[0])),
              let sig = Data(base64URLEncoded: String(parts[1])) else {
            throw StateError.invalidFormat
        }
        let expected = Data(HMAC<SHA256>.authenticationCode(for: json, using: key))
        guard expected == sig else {
            throw StateError.signatureMismatch
        }
        return json
    }

    // MARK: - GitHub OAuth (browser login)

    static func signGitHubOAuth(returnTo: String) throws -> String {
        let key = try hmacKey()
        let exp = Int64(Date().timeIntervalSince1970) + 600
        let payload = GitHubOAuthPayload(k: oauthKind, rt: returnTo, exp: exp, n: UUID().uuidString)
        let json = try JSONEncoder().encode(payload)
        return try signPayload(json, key: key)
    }

    static func verifyGitHubOAuth(state: String) throws -> String {
        let key = try hmacKey()
        let json = try verifyAndDecode(state, key: key)
        let payload = try JSONDecoder().decode(GitHubOAuthPayload.self, from: json)
        guard payload.k == oauthKind else {
            throw StateError.invalidPayloadKind
        }
        guard Int64(Date().timeIntervalSince1970) <= payload.exp else {
            throw StateError.expired
        }
        return payload.rt
    }

    // MARK: - GitHub App install

    static func signGitHubAppInstall(
        projectId: UUID,
        returnTo: String?,
        owner: String? = nil,
        repo: String? = nil
    ) throws -> String {
        let key = try hmacKey()
        let exp = Int64(Date().timeIntervalSince1970) + 3600
        let payload = GitHubAppPayload(
            k: appKind,
            pid: projectId.uuidString,
            rt: returnTo,
            owner: owner,
            repo: repo,
            exp: exp,
            n: UUID().uuidString
        )
        let json = try JSONEncoder().encode(payload)
        return try signPayload(json, key: key)
    }

    static func verifyGitHubAppInstall(state: String) throws -> (
        projectId: UUID,
        returnTo: String?,
        owner: String?,
        repo: String?
    ) {
        let key = try hmacKey()
        let json = try verifyAndDecode(state, key: key)
        let payload = try JSONDecoder().decode(GitHubAppPayload.self, from: json)
        guard payload.k == appKind else {
            throw StateError.invalidPayloadKind
        }
        guard Int64(Date().timeIntervalSince1970) <= payload.exp else {
            throw StateError.expired
        }
        guard let pid = UUID(uuidString: payload.pid) else {
            throw StateError.invalidFormat
        }
        return (pid, payload.rt, payload.owner, payload.repo)
    }
}
