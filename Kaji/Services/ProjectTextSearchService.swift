import Foundation

enum ProjectTextSearchService {
    static let maxMatches = 200
    private static let rgURL = URL(fileURLWithPath: "/opt/homebrew/bin/rg")

    static func search(query: String, in projectPath: String) async -> [ProjectTextSearchFileGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard FileManager.default.isExecutableFile(atPath: rgURL.path) else {
            return await fallbackSearch(query: trimmed, in: projectPath)
        }
        return await ProjectTextSearchProcessRunner.search(
            request: .init(
                executableURL: rgURL,
                arguments: ripgrepArguments(query: trimmed),
                projectPath: projectPath,
                currentDirectoryPath: projectPath,
                limit: maxMatches
            )
        )
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

    private static func ripgrepArguments(query: String) -> [String] {
        [
            "--hidden",
            "--no-ignore",
            "--line-number",
            "--column",
            "--color", "never",
            "--glob", "!.git",
            "--glob", "!.git/**",
            "--glob", "!node_modules",
            "--glob", "!node_modules/**",
            "--glob", "!.build",
            "--glob", "!.build/**",
            "--glob", "!build",
            "--glob", "!build/**",
            "--glob", "!DerivedData",
            "--glob", "!DerivedData/**",
            "--glob", "!dist",
            "--glob", "!dist/**",
            "--glob", "!target",
            "--glob", "!target/**",
            "--fixed-strings",
            query,
        ]
    }

    private static func fallbackSearch(query: String, in projectPath: String) async -> [ProjectTextSearchFileGroup] {
        let files = await FileSearchService.search(query: "", in: projectPath)
        let lowerQuery = query.lowercased()
        var matches: [ProjectTextSearchMatch] = []
        for file in files where matches.count < maxMatches {
            guard let contents = try? String(contentsOfFile: file.absolutePath, encoding: .utf8) else { continue }
            for (lineIndex, line) in contents.components(separatedBy: .newlines).enumerated() {
                guard let range = line.lowercased().range(of: lowerQuery) else { continue }
                let column = line.distance(from: line.startIndex, to: range.lowerBound) + 1
                matches.append(.init(
                    id: "\(file.absolutePath):\(lineIndex + 1):\(column)",
                    filePath: file.absolutePath,
                    relativePath: file.relativePath,
                    line: lineIndex + 1,
                    column: column,
                    preview: line.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
                if matches.count >= maxMatches { break }
            }
        }
        return group(matches)
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
