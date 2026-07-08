import Foundation

enum AIGatewayRedactor {
    static func redact(_ value: String) -> String {
        var output = value
        for key in ["api_key", "api-key", "authorization", "x-api-key", "token"] {
            output = output.replacingOccurrences(of: "(?i)(\(key)[^a-zA-Z0-9]+)[^\\s,}]+", with: "$1••••", options: .regularExpression)
        }
        return output
    }
}
