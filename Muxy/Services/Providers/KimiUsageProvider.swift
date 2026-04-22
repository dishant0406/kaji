import Foundation

struct KimiUsageProvider: AIUsageProvider {
    let id = "kimi"
    let displayName = "Kimi"
    let iconName = "kimi"

    private static let usageEndpoint = URL(string: "https://api.kimi.com/coding/v1/usages")
    private static let tokenEndpoint = URL(string: "https://auth.kimi.com/api/oauth/token")
    private static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"
    private static let refreshBuffer: TimeInterval = 5 * 60
    private static var credentialsPath: String { NSHomeDirectory() + "/.kimi/credentials/kimi-code.json" }

    func fetchUsageSnapshot() async -> AIProviderUsageSnapshot {
        do {
            let token = try await refreshedAccessToken()
            guard let endpoint = Self.usageEndpoint else {
                return snapshot(state: .error(message: "Unable to fetch usage"))
            }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Muxy", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return snapshot(state: .error(message: "Unable to fetch usage"))
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return snapshot(state: .unavailable(message: "Sign in to Kimi"))
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                usageLogger.error("Kimi usage request failed with status \(http.statusCode)")
                return snapshot(state: .error(message: "Usage request failed"))
            }

            let parsed = try KimiUsageParser.parse(from: data)
            guard !parsed.rows.isEmpty else {
                return snapshot(state: .unavailable(message: "No usage data"))
            }
            return AIProviderUsageSnapshot(
                providerID: id,
                providerName: parsed.planName ?? displayName,
                providerIconName: iconName,
                state: .available,
                rows: parsed.rows
            )
        } catch AIUsageAuthError.missingCredentials {
            return snapshot(state: .unavailable(message: "Sign in to Kimi"))
        } catch {
            usageLogger.error("Kimi usage request failed: \(error.localizedDescription)")
            return snapshot(state: .error(message: "Unable to fetch usage"))
        }
    }

    private func refreshedAccessToken() async throws -> String {
        let stored = try readStoredCredentials()

        if let expiresAt = stored.expiresAt,
           Date() < expiresAt.addingTimeInterval(-Self.refreshBuffer)
        {
            return stored.accessToken
        }

        guard let refreshToken = stored.refreshToken,
              let endpoint = Self.tokenEndpoint
        else {
            return stored.accessToken
        }

        do {
            let refreshed = try await AIUsageOAuth.refresh(
                endpoint: endpoint,
                formBody: [
                    "client_id": Self.clientID,
                    "grant_type": "refresh_token",
                    "refresh_token": refreshToken,
                ]
            )
            try persistCredentials(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken ?? refreshToken,
                expiresAt: refreshed.expiresAt
            )
            return refreshed.accessToken
        } catch {
            usageLogger.info("Kimi token refresh failed: \(error.localizedDescription); using stored access token")
            return stored.accessToken
        }
    }

    private struct StoredCredentials {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
    }

    private func readStoredCredentials() throws -> StoredCredentials {
        let path = Self.credentialsPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw AIUsageAuthError.missingCredentials
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = AIUsageParserSupport.string(in: payload, keys: ["access_token", "accessToken"]),
              !accessToken.isEmpty
        else {
            throw AIUsageAuthError.missingCredentials
        }

        let refreshToken = AIUsageParserSupport.string(in: payload, keys: ["refresh_token", "refreshToken"])
        let expiresAt: Date? = AIUsageParserSupport.number(in: payload, keys: ["expires_at", "expiresAt"])
            .map(AIUsageParserSupport.unixDate(from:))

        return StoredCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }

    private func persistCredentials(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date?
    ) throws {
        let path = Self.credentialsPath
        guard FileManager.default.fileExists(atPath: path) else { return }

        let fileURL = URL(fileURLWithPath: path)
        let originalData = try Data(contentsOf: fileURL)
        guard var payload = try JSONSerialization.jsonObject(with: originalData) as? [String: Any] else {
            return
        }

        payload["access_token"] = accessToken
        if let refreshToken {
            payload["refresh_token"] = refreshToken
        }
        if let expiresAt {
            payload["expires_at"] = Int(expiresAt.timeIntervalSince1970)
        }

        let updated = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try updated.write(to: fileURL, options: .atomic)
    }
}
