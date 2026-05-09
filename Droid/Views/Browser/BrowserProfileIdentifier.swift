import Foundation

enum BrowserProfileIdentifier {
    static func value(for projectPath: String) -> String {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in projectPath.utf8 {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return String(value, radix: 16)
    }
}
