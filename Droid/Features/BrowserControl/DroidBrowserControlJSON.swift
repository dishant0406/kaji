import Foundation

enum DroidBrowserControlJSON {
    static func body(_ value: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let body = String(data: data, encoding: .utf8)
        else { return "{\"error\":\"invalid_response\"}" }
        return body
    }
}
