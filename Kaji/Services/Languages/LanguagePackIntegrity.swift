import CryptoKit
import Foundation

enum LanguagePackIntegrity {
    static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func matchesSHA256(data: Data, expected: String?) -> Bool {
        guard let expected, !expected.isEmpty else { return true }
        return sha256Hex(for: data).caseInsensitiveCompare(expected) == .orderedSame
    }
}
