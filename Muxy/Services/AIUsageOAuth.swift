import Foundation

enum AIUsageOAuthError: Error {
    case refreshFailed(status: Int)
    case invalidResponse
}

struct AIUsageOAuthTokens {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
}

enum AIUsageOAuth {
    static func refresh(
        endpoint: URL,
        formBody: [String: String],
        extraHeaders: [String: String] = [:],
        session: URLSession = .shared
    ) async throws -> AIUsageOAuthTokens {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = formURLEncode(formBody).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIUsageOAuthError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw AIUsageOAuthError.refreshFailed(status: http.statusCode)
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageOAuthError.invalidResponse
        }
        guard let accessToken = AIUsageParserSupport.string(in: payload, keys: ["access_token", "accessToken"]),
              !accessToken.isEmpty
        else {
            throw AIUsageOAuthError.invalidResponse
        }

        let refreshToken = AIUsageParserSupport.string(in: payload, keys: ["refresh_token", "refreshToken"])
        let expiresAt: Date? = {
            if let absolute = AIUsageParserSupport.number(in: payload, keys: ["expires_at", "expiresAt"]) {
                return AIUsageParserSupport.unixDate(from: absolute)
            }
            if let relative = AIUsageParserSupport.number(in: payload, keys: ["expires_in", "expiresIn"]), relative > 0 {
                return Date().addingTimeInterval(relative)
            }
            return nil
        }()

        return AIUsageOAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }

    static func decodeJWTExpiry(_ token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        let payload = String(segments[1])
        guard let data = base64URLDecode(payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = AIUsageParserSupport.number(in: json, keys: ["exp"])
        else {
            return nil
        }
        return AIUsageParserSupport.unixDate(from: exp)
    }

    static func formURLEncode(_ fields: [String: String]) -> String {
        fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
    }

    private static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var normalized = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while !normalized.count.isMultiple(of: 4) {
            normalized.append("=")
        }
        return Data(base64Encoded: normalized)
    }
}
