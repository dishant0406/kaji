import Foundation

enum GitHubAccountParser {
    static func parseStatus(_ json: String, preferredHost: String? = nil) -> [GitHubAccount] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hosts = object["hosts"] as? [String: Any]
        else { return [] }

        return hosts
            .flatMap { host, value in parseAccounts(value, host: host) }
            .filter { preferredHost == nil || $0.host == preferredHost }
            .filter(\.isUsable)
            .sorted { first, second in
                if first.isActive != second.isActive { return first.isActive }
                if first.host != second.host { return first.host.localizedStandardCompare(second.host) == .orderedAscending }
                return first.login.localizedStandardCompare(second.login) == .orderedAscending
            }
    }

    private static func parseAccounts(_ value: Any, host: String) -> [GitHubAccount] {
        guard let accounts = value as? [[String: Any]] else { return [] }
        return accounts.compactMap { account in
            guard let login = account["login"] as? String else { return nil }
            let accountHost = account["host"] as? String ?? host
            return GitHubAccount(
                host: accountHost,
                login: login,
                isActive: account["active"] as? Bool ?? false,
                state: account["state"] as? String ?? "",
                tokenSource: account["tokenSource"] as? String ?? "",
                gitProtocol: account["gitProtocol"] as? String ?? ""
            )
        }
    }
}
