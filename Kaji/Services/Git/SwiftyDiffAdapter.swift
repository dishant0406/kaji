import Foundation

struct ParsedDiffRows {
    let rows: [DiffDisplayRow]
    let additions: Int
    let deletions: Int
}

enum SwiftyDiffAdapter {
    private static let minimumUnchangedRatio = 0.20
    private static let inlineTokenLimit = 128
    private static let inlineCharacterLimit = 2000
    private static let inlineTokenProductLimit = 8192

    static func parseRows(_ patch: String) -> ParsedDiffRows {
        guard !patch.isEmpty else {
            return ParsedDiffRows(rows: [], additions: 0, deletions: 0)
        }

        let lines = patch.split(separator: "\n", omittingEmptySubsequences: false)
        var rows: [DiffDisplayRow] = []
        rows.reserveCapacity(min(lines.count, 20000))
        var additions = 0
        var deletions = 0
        var oldLineNumber = 0
        var newLineNumber = 0
        var insideHunk = false

        for line in lines {
            if line.hasPrefix("@@"), let header = parseHunkHeader(line) {
                insideHunk = true
                oldLineNumber = header.oldStart
                newLineNumber = header.newStart
                rows.append(DiffDisplayRow(
                    kind: .hunk,
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    oldText: nil,
                    newText: nil,
                    text: String(line)
                ))
                continue
            }

            if line.hasPrefix("diff --git") {
                insideHunk = false
                continue
            }

            guard insideHunk else { continue }
            guard !line.hasPrefix("\\") else { continue }

            if line.hasPrefix("+") {
                let content = String(line.dropFirst())
                rows.append(DiffDisplayRow(
                    kind: .addition,
                    oldLineNumber: nil,
                    newLineNumber: newLineNumber,
                    oldText: nil,
                    newText: content,
                    text: "+\(content)"
                ))
                newLineNumber += 1
                additions += 1
                continue
            }

            if line.hasPrefix("-") {
                let content = String(line.dropFirst())
                rows.append(DiffDisplayRow(
                    kind: .deletion,
                    oldLineNumber: oldLineNumber,
                    newLineNumber: nil,
                    oldText: content,
                    newText: nil,
                    text: "-\(content)"
                ))
                oldLineNumber += 1
                deletions += 1
                continue
            }

            let content = line.hasPrefix(" ") ? String(line.dropFirst()) : String(line)
            rows.append(DiffDisplayRow(
                kind: .context,
                oldLineNumber: oldLineNumber,
                newLineNumber: newLineNumber,
                oldText: content,
                newText: content,
                text: " \(content)"
            ))
            oldLineNumber += 1
            newLineNumber += 1
        }

        return ParsedDiffRows(
            rows: applyingInlineSegments(to: rows),
            additions: additions,
            deletions: deletions
        )
    }

    static func collapseContextRows(_ rows: [DiffDisplayRow]) -> [DiffDisplayRow] {
        var output: [DiffDisplayRow] = []
        var index = 0
        let leadingContext = 3
        let trailingContext = 3
        let collapseThreshold = 12

        while index < rows.count {
            let row = rows[index]
            if row.kind != .context {
                output.append(row)
                index += 1
                continue
            }

            var end = index
            while end < rows.count, rows[end].kind == .context {
                end += 1
            }

            let runLength = end - index
            if runLength <= collapseThreshold {
                output.append(contentsOf: rows[index ..< end])
            } else {
                let startKeepEnd = index + leadingContext
                let endKeepStart = end - trailingContext
                output.append(contentsOf: rows[index ..< startKeepEnd])
                output.append(DiffDisplayRow(
                    kind: .collapsed,
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    oldText: nil,
                    newText: nil,
                    text: "\(runLength - leadingContext - trailingContext) unmodified lines"
                ))
                output.append(contentsOf: rows[endKeepStart ..< end])
            }

            index = end
        }

        return output
    }

    private static func parseHunkHeader(_ line: Substring) -> (oldStart: Int, newStart: Int)? {
        var index = line.startIndex
        guard line.distance(from: index, to: line.endIndex) >= 4 else { return nil }
        guard line[index] == "@" else { return nil }
        line.formIndex(after: &index)
        guard index < line.endIndex, line[index] == "@" else { return nil }
        line.formIndex(after: &index)
        skipSpaces(in: line, index: &index)
        guard index < line.endIndex, line[index] == "-" else { return nil }
        line.formIndex(after: &index)
        guard let oldStart = parsePositiveInt(in: line, index: &index) else { return nil }
        skipCount(in: line, index: &index)
        skipSpaces(in: line, index: &index)
        guard index < line.endIndex, line[index] == "+" else { return nil }
        line.formIndex(after: &index)
        guard let newStart = parsePositiveInt(in: line, index: &index) else { return nil }
        return (oldStart, newStart)
    }

    private static func skipSpaces(in line: Substring, index: inout Substring.Index) {
        while index < line.endIndex, line[index] == " " {
            line.formIndex(after: &index)
        }
    }

    private static func skipCount(in line: Substring, index: inout Substring.Index) {
        guard index < line.endIndex, line[index] == "," else { return }
        line.formIndex(after: &index)
        while index < line.endIndex, line[index].isNumber {
            line.formIndex(after: &index)
        }
    }

    private static func parsePositiveInt(in line: Substring, index: inout Substring.Index) -> Int? {
        var value = 0
        var consumed = false
        while index < line.endIndex, let digit = line[index].wholeNumberValue {
            value = value * 10 + digit
            consumed = true
            line.formIndex(after: &index)
        }
        return consumed ? value : nil
    }

    private static func applyingInlineSegments(to rows: [DiffDisplayRow]) -> [DiffDisplayRow] {
        var output: [DiffDisplayRow] = []
        output.reserveCapacity(rows.count)
        var index = 0

        while index < rows.count {
            if rows[index].kind != .deletion {
                output.append(rows[index])
                index += 1
                continue
            }

            var deletions: [DiffDisplayRow] = []
            while index < rows.count, rows[index].kind == .deletion {
                deletions.append(rows[index])
                index += 1
            }

            var additions: [DiffDisplayRow] = []
            while index < rows.count, rows[index].kind == .addition {
                additions.append(rows[index])
                index += 1
            }

            if additions.isEmpty {
                output.append(contentsOf: deletions)
                continue
            }

            let pairCount = min(deletions.count, additions.count)
            for pairIndex in 0 ..< pairCount {
                let deletion = deletions[pairIndex]
                let addition = additions[pairIndex]
                if let oldText = deletion.oldText,
                   let newText = addition.newText,
                   let segments = inlineSegments(oldText: oldText, newText: newText)
                {
                    output.append(copyRow(deletion, oldInlineSegments: segments.old, newInlineSegments: nil))
                    output.append(copyRow(addition, oldInlineSegments: nil, newInlineSegments: segments.new))
                } else {
                    output.append(deletion)
                    output.append(addition)
                }
            }

            if deletions.count > pairCount {
                output.append(contentsOf: deletions[pairCount...])
            }
            if additions.count > pairCount {
                output.append(contentsOf: additions[pairCount...])
            }
        }

        return output
    }

    private static func copyRow(
        _ row: DiffDisplayRow,
        oldInlineSegments: [DiffInlineSegment]?,
        newInlineSegments: [DiffInlineSegment]?
    ) -> DiffDisplayRow {
        DiffDisplayRow(
            kind: row.kind,
            oldLineNumber: row.oldLineNumber,
            newLineNumber: row.newLineNumber,
            oldText: row.oldText,
            newText: row.newText,
            text: row.text,
            oldInlineSegments: oldInlineSegments,
            newInlineSegments: newInlineSegments
        )
    }

    private static func inlineSegments(
        oldText: String,
        newText: String
    ) -> (old: [DiffInlineSegment], new: [DiffInlineSegment])? {
        guard oldText.utf16.count <= inlineCharacterLimit, newText.utf16.count <= inlineCharacterLimit else { return nil }
        let oldTokens = inlineTokens(oldText)
        let newTokens = inlineTokens(newText)
        guard !oldTokens.isEmpty, !newTokens.isEmpty else { return nil }
        guard oldTokens.count <= inlineTokenLimit, newTokens.count <= inlineTokenLimit else { return nil }
        guard oldTokens.count * newTokens.count <= inlineTokenProductLimit else { return nil }
        guard hasCandidateSimilarity(oldTokens: oldTokens, newTokens: newTokens, oldText: oldText, newText: newText) else { return nil }

        var lengths = Array(repeating: Array(repeating: 0, count: newTokens.count + 1), count: oldTokens.count + 1)
        for oldIndex in stride(from: oldTokens.count - 1, through: 0, by: -1) {
            for newIndex in stride(from: newTokens.count - 1, through: 0, by: -1) {
                if oldTokens[oldIndex] == newTokens[newIndex] {
                    lengths[oldIndex][newIndex] = lengths[oldIndex + 1][newIndex + 1] + 1
                } else {
                    lengths[oldIndex][newIndex] = max(lengths[oldIndex + 1][newIndex], lengths[oldIndex][newIndex + 1])
                }
            }
        }

        var oldSegments: [DiffInlineSegment] = []
        var newSegments: [DiffInlineSegment] = []
        var unchangedLength = 0
        var oldIndex = 0
        var newIndex = 0

        while oldIndex < oldTokens.count, newIndex < newTokens.count {
            if oldTokens[oldIndex] == newTokens[newIndex] {
                appendSegment(text: oldTokens[oldIndex], emphasized: false, to: &oldSegments)
                appendSegment(text: newTokens[newIndex], emphasized: false, to: &newSegments)
                if oldTokens[oldIndex].contains(where: { !$0.isWhitespace }) {
                    unchangedLength += oldTokens[oldIndex].trimmingCharacters(in: .whitespacesAndNewlines).count
                }
                oldIndex += 1
                newIndex += 1
            } else if lengths[oldIndex + 1][newIndex] >= lengths[oldIndex][newIndex + 1] {
                appendSegment(text: oldTokens[oldIndex], emphasized: true, to: &oldSegments)
                oldIndex += 1
            } else {
                appendSegment(text: newTokens[newIndex], emphasized: true, to: &newSegments)
                newIndex += 1
            }
        }

        while oldIndex < oldTokens.count {
            appendSegment(text: oldTokens[oldIndex], emphasized: true, to: &oldSegments)
            oldIndex += 1
        }
        while newIndex < newTokens.count {
            appendSegment(text: newTokens[newIndex], emphasized: true, to: &newSegments)
            newIndex += 1
        }

        let totalLength = max(
            oldText.trimmingCharacters(in: .whitespacesAndNewlines).count,
            newText.trimmingCharacters(in: .whitespacesAndNewlines).count
        )
        guard totalLength > 0 else { return nil }
        guard Double(unchangedLength) / Double(totalLength) >= minimumUnchangedRatio else { return nil }
        return (oldSegments, newSegments)
    }

    private static func hasCandidateSimilarity(
        oldTokens: [String],
        newTokens: [String],
        oldText: String,
        newText: String
    ) -> Bool {
        let totalLength = max(
            oldText.trimmingCharacters(in: .whitespacesAndNewlines).count,
            newText.trimmingCharacters(in: .whitespacesAndNewlines).count
        )
        guard totalLength > 0 else { return false }

        let oldMeaningful = Set(oldTokens.filter { $0.contains { !$0.isWhitespace } })
        guard !oldMeaningful.isEmpty else { return false }

        var sharedLength = 0
        for token in newTokens where oldMeaningful.contains(token) && token.contains(where: { !$0.isWhitespace }) {
            sharedLength += token.trimmingCharacters(in: .whitespacesAndNewlines).count
        }

        return Double(sharedLength) / Double(totalLength) >= minimumUnchangedRatio
    }

    private static func inlineTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentKind: InlineTokenKind?

        for character in text {
            let kind = InlineTokenKind(character)
            if currentKind == kind {
                current.append(character)
            } else {
                if !current.isEmpty {
                    tokens.append(current)
                }
                current = String(character)
                currentKind = kind
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func appendSegment(text: String, emphasized: Bool, to segments: inout [DiffInlineSegment]) {
        guard !text.isEmpty else { return }
        if let last = segments.last, last.emphasized == emphasized {
            segments[segments.count - 1] = DiffInlineSegment(text: last.text + text, emphasized: emphasized)
        } else {
            segments.append(DiffInlineSegment(text: text, emphasized: emphasized))
        }
    }
}

private enum InlineTokenKind: Equatable {
    case whitespace
    case word
    case punctuation

    init(_ character: Character) {
        if character.isWhitespace {
            self = .whitespace
        } else if character.isLetter || character.isNumber || character == "_" {
            self = .word
        } else {
            self = .punctuation
        }
    }
}
