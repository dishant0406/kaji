import Foundation

struct CopilotUsageProvider: AIUsageProvider {
    let id = "copilot"
    let displayName = "Copilot"
    let iconName = "copilot"

    private static let endpoint = URL(string: "https://api.github.com/copilot_internal/user")

    func fetchUsageSnapshot() async -> AIProviderUsageSnapshot {
        await AIUsageSession.fetchSnapshot(
            provider: self,
            messages: AIUsageSessionMessages(
                missingCredentials: "Sign in to Copilot",
                unauthenticated: "Copilot token lacks usage access"
            ),
            buildRequest: {
                guard let endpoint = Self.endpoint else { throw AIUsageAuthError.missingCredentials }
                let token = try Self.readToken()
                var request = URLRequest(url: endpoint)
                request.httpMethod = "GET"
                request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
                request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
                request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
                request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
                return request
            },
            parse: CopilotUsageParser.parseMetricRows(from:)
        )
    }

    static func readToken(
        env: [String: String] = ProcessInfo.processInfo.environment,
        keychainReader: ((String) -> String?)? = nil,
        homeDirectory: String = NSHomeDirectory(),
        fileExists: ((String) -> Bool)? = nil,
        dataReader: ((String) throws -> Data)? = nil
    ) throws -> String {
        let doesFileExist = fileExists ?? { FileManager.default.fileExists(atPath: $0) }
        let readData = dataReader ?? { try Data(contentsOf: URL(fileURLWithPath: $0)) }
        let readKeychainValue = keychainReader ?? { AIUsageTokenReader.fromKeychain(service: $0) }

        if let token = AIUsageTokenReader.fromEnvironment(
            keys: ["COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"],
            env: env
        ) {
            return token
        }

        let hostsPath = homeDirectory + "/.config/github-copilot/hosts.json"
        if doesFileExist(hostsPath) {
            let data = try readData(hostsPath)
            if let token = try CopilotUsageParser.extractToken(fromHostsData: data), !token.isEmpty {
                return token
            }
        }

        if let rawGh = readKeychainValue("gh:github.com") {
            let trimmed = rawGh.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokenCandidate: String
            if trimmed.hasPrefix("go-keyring-base64:") {
                let encoded = String(trimmed.dropFirst("go-keyring-base64:".count))
                if let data = Data(base64Encoded: encoded), let decoded = String(data: data, encoding: .utf8) {
                    tokenCandidate = decoded
                } else {
                    tokenCandidate = trimmed
                }
            } else {
                tokenCandidate = trimmed
            }

            let normalized = tokenCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return normalized
            }
        }

        let ghHostsPath = homeDirectory + "/.config/gh/hosts.yml"
        if doesFileExist(ghHostsPath) {
            let data = try readData(ghHostsPath)
            if let yaml = String(data: data, encoding: .utf8),
               let token = CopilotUsageParser.extractToken(fromGHHostsYAML: yaml),
               !token.isEmpty
            {
                return token
            }
        }

        throw AIUsageAuthError.missingCredentials
    }
}
