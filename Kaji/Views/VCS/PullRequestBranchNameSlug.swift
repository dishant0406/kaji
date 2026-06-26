import Foundation

enum PullRequestBranchNameSlug {
    static func make(from title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = title.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(String(scalars).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-").prefix(20))
    }
}
