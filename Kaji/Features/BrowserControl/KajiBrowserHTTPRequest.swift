import Foundation

struct KajiBrowserHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: String

    init?(raw: String) {
        let parts = raw.components(separatedBy: "\r\n\r\n")
        guard let head = parts.first else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let tokens = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard tokens.count >= 2 else { return nil }
        method = tokens[0]
        path = tokens[1]
        headers = Dictionary(uniqueKeysWithValues: lines.dropFirst().compactMap(Self.header))
        body = parts.dropFirst().joined(separator: "\r\n\r\n")
    }

    private static func header(_ line: String) -> (String, String)? {
        guard let separator = line.firstIndex(of: ":") else { return nil }
        let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : (key, value)
    }
}
