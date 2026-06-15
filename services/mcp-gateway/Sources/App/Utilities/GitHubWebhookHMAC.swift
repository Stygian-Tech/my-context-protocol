import Crypto
import Foundation

enum GitHubWebhookHMAC {
    /// Constant-time verification of `X-Hub-Signature-256` (`sha256=<hex>`).
    static func isValid(signatureHeader: String, body: Data, secret: String) -> Bool {
        guard signatureHeader.hasPrefix("sha256=") else { return false }
        let hex = String(signatureHeader.dropFirst(7))
        guard let provided = decodeHex(hex) else { return false }
        let key = SymmetricKey(data: Data(secret.utf8))
        return HMAC<SHA256>.isValidAuthenticationCode(provided, authenticating: body, using: key)
    }

    private static func decodeHex(_ hex: String) -> Data? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count.isMultiple(of: 2), !trimmed.isEmpty else { return nil }
        var data = Data(capacity: trimmed.count / 2)
        var idx = trimmed.startIndex
        while idx < trimmed.endIndex {
            let next = trimmed.index(idx, offsetBy: 2)
            guard let byte = UInt8(trimmed[idx ..< next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        return data
    }
}
