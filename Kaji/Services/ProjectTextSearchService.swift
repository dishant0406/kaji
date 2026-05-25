import Foundation

enum ProjectTextSearchService {
    static let maxMatches = 200

    static func search(query: String, in projectPath: String) async -> [ProjectTextSearchFileGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return await (try? FFFSearchService.searchText(query: trimmed, in: projectPath, limit: maxMatches)) ?? []
    }

    static func replace(query: String, groups: [ProjectTextSearchFileGroup], with replacement: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let changed = try replaceSync(query: query, groups: groups, with: replacement)
                    continuation.resume(returning: changed)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func group(_ matches: [ProjectTextSearchMatch]) -> [ProjectTextSearchFileGroup] {
        let grouped = Dictionary(grouping: matches, by: \.filePath)
        return grouped.keys.sorted().compactMap { filePath in
            guard let matches = grouped[filePath], let first = matches.first else { return nil }
            return ProjectTextSearchFileGroup(
                id: filePath,
                filePath: filePath,
                relativePath: first.relativePath,
                matches: matches.sorted { lhs, rhs in
                    lhs.line == rhs.line ? lhs.column < rhs.column : lhs.line < rhs.line
                }
            )
        }
    }

    private static func replaceSync(query: String, groups: [ProjectTextSearchFileGroup], with replacement: String) throws -> [String] {
        let matchLength = (query as NSString).length
        guard matchLength > 0 else { return [] }
        var changedPaths: [String] = []
        for group in groups {
            let url = URL(fileURLWithPath: group.filePath)
            let original = try String(contentsOf: url, encoding: .utf8)
            let lines = original.components(separatedBy: .newlines)
            var updated = lines
            let matchesByLine = Dictionary(grouping: group.matches, by: \.line)
            for lineNumber in matchesByLine.keys.sorted().reversed() {
                let index = lineNumber - 1
                guard index >= 0, index < updated.count, let lineMatches = matchesByLine[lineNumber] else { continue }
                var nsLine = updated[index] as NSString
                for match in lineMatches.sorted(by: { $0.column > $1.column }) {
                    let range = NSRange(location: max(0, match.column - 1), length: matchLength)
                    guard range.length > 0, NSMaxRange(range) <= nsLine.length else { continue }
                    nsLine = nsLine.replacingCharacters(in: range, with: replacement) as NSString
                }
                updated[index] = nsLine as String
            }
            let next = updated.joined(separator: "\n")
            guard next != original else { continue }
            try next.write(to: url, atomically: true, encoding: .utf8)
            changedPaths.append(group.filePath)
        }
        return changedPaths
    }
}
