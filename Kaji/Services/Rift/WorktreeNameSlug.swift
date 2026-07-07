import Foundation

enum WorktreeNameSlug {
    static func slug(from name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let collapsed = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? UUID().uuidString : collapsed
    }
}
