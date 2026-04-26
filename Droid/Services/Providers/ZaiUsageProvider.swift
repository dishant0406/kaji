import Foundation

struct ZaiUsageProvider: AIUsageProvider {
    let id = "zai"
    let displayName = "Z.ai"
    let iconName = "zai"

    private static let subscriptionURL = URL(string: "https://api.z.ai/api/biz/subscription/list")
    private static let quotaURL = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")

    func fetchUsageSnapshot() async -> AIProviderUsageSnapshot {
        do {
            guard let subscriptionURL = Self.subscriptionURL, let quotaURL = Self.quotaURL else {
                return snapshot(state: .error(message: "Unable to fetch usage"))
            }
            let apiKey = try Self.readToken()
            let headers = [
                "Authorization": "Bearer \(apiKey)",
                "Accept": "application/json",
            ]

            let subscriptionData: Data?
            do {
                subscriptionData = try await Self.fetch(url: subscriptionURL, headers: headers).data
            } catch {
                usageLogger.error("Z.ai subscription request failed: \(error.localizedDescription)")
                subscriptionData = nil
            }
            let quota = try await Self.fetch(url: quotaURL, headers: headers)

            if quota.statusCode == 401 || quota.statusCode == 403 {
                return snapshot(state: .unavailable(message: "Invalid Z.ai API key"))
            }
            guard (200 ..< 300).contains(quota.statusCode) else {
                usageLogger.error("Z.ai usage request failed with status \(quota.statusCode)")
                return snapshot(state: .error(message: "Usage request failed"))
            }

            let rows = try ZaiUsageParser.parseMetricRows(quotaData: quota.data)
            guard !rows.isEmpty else {
                return snapshot(state: .unavailable(message: "No usage data"))
            }

            let planName = subscriptionData.flatMap { ZaiUsageParser.parsePlanName(subscriptionData: $0) } ?? displayName
            return AIProviderUsageSnapshot(
                providerID: id,
                providerName: planName,
                providerIconName: iconName,
                state: .available,
                rows: rows
            )
        } catch AIUsageAuthError.missingCredentials {
            return snapshot(state: .unavailable(message: "Set ZAI_API_KEY or GLM_API_KEY"))
        } catch {
            usageLogger.error("Z.ai usage request failed: \(error.localizedDescription)")
            return snapshot(state: .error(message: "Unable to fetch usage"))
        }
    }

    static func readToken(env: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        if let token = AIUsageTokenReader.fromEnvironment(keys: ["ZAI_API_KEY", "GLM_API_KEY"], env: env) {
            return token
        }
        throw AIUsageAuthError.missingCredentials
    }

    private static func fetch(url: URL, headers: [String: String]) async throws -> (statusCode: Int, data: Data) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (http.statusCode, data)
    }
}
