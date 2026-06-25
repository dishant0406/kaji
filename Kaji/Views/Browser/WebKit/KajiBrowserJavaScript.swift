import Foundation
import WebKit

enum KajiBrowserJavaScript {
    @MainActor
    static func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    @MainActor
    static func string(_ script: String, in webView: WKWebView) async throws -> String {
        let value = try await evaluate(script, in: webView)
        if value is NSNull { return "" }
        return value as? String ?? value.map { String(describing: $0) } ?? ""
    }

    static func json(_ value: Any?) -> Any {
        guard let value else { return NSNull() }
        if value is NSNull { return NSNull() }
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value }
        if let value = value as? [Any] { return value.map(json) }
        if let value = value as? [String: Any] { return value.mapValues(json) }
        return String(describing: value)
    }

    static func literal(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let text = String(data: data, encoding: .utf8),
              text.count >= 2
        else {
            return "\"\""
        }
        return String(text.dropFirst().dropLast())
    }
}
