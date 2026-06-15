import Crypto
import Foundation
import Vapor

enum TokenEncryption {
    static func encrypt(_ plaintext: String) throws -> String {
        guard let key = key() else {
            throw TokenEncryptionError.keyNotConfigured
        }
        let data = Data(plaintext.utf8)
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw TokenEncryptionError.encryptionFailed
        }
        return combined.base64EncodedString()
    }

    static func decrypt(_ ciphertext: String) throws -> String {
        guard let key = key() else {
            throw TokenEncryptionError.keyNotConfigured
        }
        guard let data = Data(base64Encoded: ciphertext) else {
            throw TokenEncryptionError.invalidCiphertext
        }
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decrypted = try AES.GCM.open(sealedBox, using: key)
        guard let string = String(data: decrypted, encoding: .utf8) else {
            throw TokenEncryptionError.decryptionFailed
        }
        return string
    }

    private static func key() -> SymmetricKey? {
        guard let keyBase64 = Environment.get("ENCRYPTION_KEY"), !keyBase64.isEmpty,
              let keyData = Data(base64Encoded: keyBase64), keyData.count == 32 else {
            return nil
        }
        return SymmetricKey(data: keyData)
    }
}

enum TokenEncryptionError: Error {
    case keyNotConfigured
    case encryptionFailed
    case decryptionFailed
    case invalidCiphertext
}
