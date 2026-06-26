import Foundation

enum GitHubRemoteURLParser {
    static func host(from remoteURL: String) -> String? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let host = url.host(percentEncoded: false) {
            return host
        }

        if let atIndex = trimmed.firstIndex(of: "@"),
           let colonIndex = trimmed[atIndex...].firstIndex(of: ":")
        {
            let start = trimmed.index(after: atIndex)
            guard start < colonIndex else { return nil }
            return String(trimmed[start ..< colonIndex])
        }

        return nil
    }
}
