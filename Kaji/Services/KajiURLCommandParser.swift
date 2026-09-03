import Foundation

enum KajiURLCommand: Equatable {
    case openProject(path: String)
}

enum KajiURLCommandParser {
    static func parse(_ url: URL) -> KajiURLCommand? {
        guard url.scheme == "kaji" else { return nil }
        guard url.host(percentEncoded: false) == "open-project" else { return nil }
        guard let payload = url.pathComponents.dropFirst().first else { return nil }
        guard url.pathComponents.dropFirst().count == 1 else { return nil }
        guard let path = decodeBase64URL(payload), !path.isEmpty else { return nil }
        return .openProject(path: path)
    }

    static func encodePath(_ path: String) -> String {
        Data(path.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBase64URL(_ payload: String) -> String? {
        guard !payload.isEmpty else { return nil }
        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder == 1 {
            return nil
        }
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
