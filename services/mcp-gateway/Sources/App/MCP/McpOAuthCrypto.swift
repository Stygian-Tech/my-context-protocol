import Crypto
import Foundation

enum McpOAuthCrypto {
    static func sha256Hex(_ string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func randomToken(prefix: String, byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in bytes.indices {
            bytes[i] = UInt8.random(in: 0 ... 255)
        }
        return prefix + Data(bytes).base64URLEncodedString
    }
}
