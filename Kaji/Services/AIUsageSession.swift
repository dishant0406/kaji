import Foundation

struct AIUsageSessionMessages {
    let missingCredentials: String
    let unauthenticated: String
    let requestFailed: String
    let genericError: String
    let noData: String

    init(
        missingCredentials: String,
        unauthenticated: String,
        requestFailed: String = "Usage request failed",
        genericError: String = "Unable to fetch usage",
        noData: String = "No usage data"
    ) {
        self.missingCredentials = missingCredentials
        self.unauthenticated = unauthenticated
        self.requestFailed = requestFailed
        self.genericError = genericError
        self.noData = noData
    }
}

enum AIUsageSession {
    static func fetchSnapshot(
        provider: any AIUsageProvider,
        messages: AIUsageSessionMessages,
        session: URLSession = .shared,
        buildRequest: @Sendable () throws -> URLRequest,
        parse: @Sendable (Data) throws -> [AIUsageMetricRow]
    ) async -> AIProviderUsageSnapshot {
        do {
            let request = try buildRequest()
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return provider.snapshot(state: .error(message: messages.genericError))
            }

            if http.statusCode == 401 || http.statusCode == 403 {
                return provider.snapshot(state: .unavailable(message: messages.unauthenticated))
            }

            guard (200 ..< 300).contains(http.statusCode) else {
                usageLogger.error("\(provider.id) usage request failed with status \(http.statusCode)")
                return provider.snapshot(state: .error(message: messages.requestFailed))
            }

            let rows = try parse(data)
            if rows.isEmpty {
                return provider.snapshot(state: .unavailable(message: messages.noData))
            }
            return provider.snapshot(state: .available, rows: rows)
        } catch AIUsageAuthError.missingCredentials {
            return provider.snapshot(state: .unavailable(message: messages.missingCredentials))
        } catch {
            usageLogger.error("\(provider.id) usage request failed: \(error.localizedDescription)")
            return provider.snapshot(state: .error(message: messages.genericError))
        }
    }
}
