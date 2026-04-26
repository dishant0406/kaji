import Foundation

enum FileSearchRanker {
    static func rankInitialCandidates(_ candidates: [FileSearchResult], maxResults: Int) -> [FileSearchResult] {
        candidates
            .sorted { lhs, rhs in
                if lhs.relativePath.count != rhs.relativePath.count {
                    return lhs.relativePath.count < rhs.relativePath.count
                }
                return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
            }
            .prefix(maxResults)
            .map(\.self)
    }

    static func rankCandidates(_ candidates: [FileSearchResult], query: String, maxResults: Int) -> [FileSearchResult] {
        let queryCharacters = Array(query.lowercased())
        guard !queryCharacters.isEmpty else { return [] }
        let preferPath = query.contains("/")

        let scored = candidates.compactMap { candidate -> (FileSearchResult, Int)? in
            guard let score = FileSearchScorer.score(
                queryLower: queryCharacters,
                fileName: candidate.fileName,
                relativePath: candidate.relativePath,
                preferPath: preferPath
            )
            else { return nil }
            return (candidate, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.0.relativePath.count != rhs.0.relativePath.count {
                    return lhs.0.relativePath.count < rhs.0.relativePath.count
                }
                return lhs.0.relativePath.localizedCaseInsensitiveCompare(rhs.0.relativePath) == .orderedAscending
            }
            .prefix(maxResults)
            .map(\.0)
    }
}

private enum FileSearchScorer {
    static func score(
        queryLower: [Character],
        fileName: String,
        relativePath: String,
        preferPath: Bool
    ) -> Int? {
        let pathLower = Array(relativePath.lowercased())
        let pathOriginal = Array(relativePath)

        if preferPath {
            guard let pathScore = scoreAgainst(
                queryLower: queryLower,
                targetLower: pathLower,
                targetOriginal: pathOriginal
            )
            else { return nil }
            return pathScore.score + 1000
        }

        let fileNameLower = Array(fileName.lowercased())
        if let nameScore = scoreAgainst(
            queryLower: queryLower,
            targetLower: fileNameLower,
            targetOriginal: Array(fileName)
        ) {
            return nameScore.score + fileNamePositionBonus(nameScore: nameScore, fileNameLength: fileNameLower.count) + 1000
        }

        if let pathScore = scoreAgainst(
            queryLower: queryLower,
            targetLower: pathLower,
            targetOriginal: pathOriginal
        ) {
            return pathScore.score
        }

        return nil
    }

    private struct SubsequenceScore {
        let score: Int
        let firstMatchIndex: Int
    }

    private static func scoreAgainst(
        queryLower: [Character],
        targetLower: [Character],
        targetOriginal: [Character]
    ) -> SubsequenceScore? {
        guard !queryLower.isEmpty, targetLower.count >= queryLower.count else { return nil }

        if queryLower.count == targetLower.count, queryLower == targetLower {
            return SubsequenceScore(score: 10000, firstMatchIndex: 0)
        }

        if let range = rangeOfContiguous(query: queryLower, in: targetLower) {
            var score = 5000 - range.lowerBound * 10
            if range.lowerBound == 0 {
                score += 1500
            }
            if range.lowerBound > 0, isSeparator(targetLower[range.lowerBound - 1]) {
                score += 800
            }
            return SubsequenceScore(score: score, firstMatchIndex: range.lowerBound)
        }

        return subsequenceScore(queryLower: queryLower, targetLower: targetLower, targetOriginal: targetOriginal)
    }

    private static func rangeOfContiguous(query: [Character], in target: [Character]) -> Range<Int>? {
        guard query.count <= target.count else { return nil }
        for start in 0 ... (target.count - query.count) {
            var matched = true
            for offset in 0 ..< query.count where target[start + offset] != query[offset] {
                matched = false
                break
            }
            if matched {
                return start ..< (start + query.count)
            }
        }
        return nil
    }

    private static func subsequenceScore(
        queryLower: [Character],
        targetLower: [Character],
        targetOriginal: [Character]
    ) -> SubsequenceScore? {
        var score = 0
        var queryIndex = 0
        var previousMatchIndex = -2
        var firstMatchIndex = -1

        for targetIndex in 0 ..< targetLower.count {
            if queryIndex >= queryLower.count { break }
            if targetLower[targetIndex] != queryLower[queryIndex] { continue }

            if firstMatchIndex < 0 {
                firstMatchIndex = targetIndex
            }

            var characterScore = 10
            if targetIndex == previousMatchIndex + 1 {
                characterScore += 40
            }
            if targetIndex == 0 {
                characterScore += 50
            } else {
                let previousCharacter = targetLower[targetIndex - 1]
                if isSeparator(previousCharacter) {
                    characterScore += 35
                }
                let originalCharacter = targetOriginal[targetIndex]
                if originalCharacter.isUppercase, !previousCharacter.isUppercase {
                    characterScore += 25
                }
            }

            score += characterScore
            previousMatchIndex = targetIndex
            queryIndex += 1
        }

        guard queryIndex == queryLower.count else { return nil }

        if firstMatchIndex >= 0 {
            score -= firstMatchIndex
        }
        return SubsequenceScore(score: score, firstMatchIndex: max(firstMatchIndex, 0))
    }

    private static func fileNamePositionBonus(nameScore: SubsequenceScore, fileNameLength: Int) -> Int {
        guard fileNameLength > 0 else { return 0 }
        return max(0, 60 - nameScore.firstMatchIndex * 5)
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character == "_" || character == "-" || character == "." || character == "/" || character == " "
    }
}
