import Foundation

struct GitHubAccount: Hashable, Identifiable {
    let host: String
    let login: String
    let isActive: Bool
    let state: String
    let tokenSource: String
    let gitProtocol: String

    var id: String { "\(host):\(login)" }

    var isUsable: Bool {
        let normalizedState = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedState == "success" || normalizedState.contains("logged in")
    }

    var menuTitle: String {
        isActive ? "\(login) @ \(host) active" : "\(login) @ \(host)"
    }
}
