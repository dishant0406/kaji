import Foundation

@MainActor
final class TextBackingStore {
    private(set) var lines: [String] = [""]
    private var fullTextCache: String?
    private var cachedUTF16Length = 0

    var lineCount: Int { lines.count }
    var utf16Length: Int { cachedUTF16Length }

    func loadFromText(_ text: String) {
        let split = text.split(separator: "\n", omittingEmptySubsequences: false)
        lines = split.isEmpty ? [""] : split.map(String.init)
        fullTextCache = text
        cachedUTF16Length = text.utf16.count
    }

    func appendText(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        fullTextCache = nil
        cachedUTF16Length += chunk.utf16.count
        let split = chunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = split.first else { return }
        if !lines.isEmpty {
            lines[lines.count - 1] += first
        } else {
            lines.append(first)
        }
        for line in split.dropFirst() {
            lines.append(line)
        }
    }

    func finishLoading() {}

    func line(at index: Int) -> String {
        guard index >= 0, index < lines.count else { return "" }
        return lines[index]
    }

    func textForRange(_ range: Range<Int>) -> String {
        let clamped = max(0, range.lowerBound) ..< min(lines.count, range.upperBound)
        guard !clamped.isEmpty else { return "" }
        return lines[clamped].joined(separator: "\n")
    }

    func fullText() -> String {
        if let fullTextCache {
            return fullTextCache
        }
        let text = lines.joined(separator: "\n")
        fullTextCache = text
        return text
    }

    func utf16LengthExceeds(_ limit: Int) -> Bool {
        guard limit >= 0 else { return true }
        return cachedUTF16Length > limit
    }

    func replaceLines(in range: Range<Int>, with newLines: [String]) -> [String] {
        let clamped = max(0, range.lowerBound) ..< min(lines.count, range.upperBound)
        let oldLineCount = lines.count
        let old = Array(lines[clamped])
        let oldTextLength = Self.linesUTF16Length(old)
        let newTextLength = Self.linesUTF16Length(newLines)
        lines.replaceSubrange(clamped, with: newLines)
        cachedUTF16Length += newTextLength - oldTextLength
        cachedUTF16Length += Self.separatorCount(forLineCount: lines.count) - Self.separatorCount(forLineCount: oldLineCount)
        fullTextCache = nil
        return old
    }

    func insertLines(_ newLines: [String], at index: Int) {
        guard !newLines.isEmpty else { return }
        let clamped = min(max(0, index), lines.count)
        let oldLineCount = lines.count
        lines.insert(contentsOf: newLines, at: clamped)
        cachedUTF16Length += Self.linesUTF16Length(newLines)
        cachedUTF16Length += Self.separatorCount(forLineCount: lines.count) - Self.separatorCount(forLineCount: oldLineCount)
        fullTextCache = nil
    }

    func applyMonacoEdits(_ edits: [MonacoTextEdit]) {
        guard !edits.isEmpty else { return }
        let orderedEdits = edits.sorted { lhs, rhs in
            if lhs.range.startLineNumber != rhs.range.startLineNumber {
                return lhs.range.startLineNumber > rhs.range.startLineNumber
            }
            return lhs.range.startColumn > rhs.range.startColumn
        }
        for edit in orderedEdits {
            applyMonacoEdit(edit)
        }
    }

    private func applyMonacoEdit(_ edit: MonacoTextEdit) {
        let startLineIndex = min(max(0, edit.range.startLineNumber - 1), max(0, lines.count - 1))
        let endLineIndex = min(max(startLineIndex, edit.range.endLineNumber - 1), max(0, lines.count - 1))
        let startLine = line(at: startLineIndex)
        let endLine = line(at: endLineIndex)
        let startColumn = min(max(0, edit.range.startColumn - 1), startLine.utf16.count)
        let endColumn = min(max(0, edit.range.endColumn - 1), endLine.utf16.count)
        let prefix = Self.utf16Prefix(startLine, length: startColumn)
        let suffix = Self.utf16Suffix(endLine, from: endColumn)
        let replacement = edit.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let replacementLines = replacement.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines: [String]
        if replacementLines.isEmpty {
            newLines = [prefix + suffix]
        } else if replacementLines.count == 1 {
            newLines = [prefix + replacementLines[0] + suffix]
        } else {
            var lines = replacementLines
            lines[0] = prefix + lines[0]
            lines[lines.count - 1] += suffix
            newLines = lines
        }
        _ = replaceLines(in: startLineIndex ..< endLineIndex + 1, with: newLines)
    }

    private static func utf16Prefix(_ text: String, length: Int) -> String {
        let nsText = text as NSString
        let safeLength = min(max(0, length), nsText.length)
        return nsText.substring(to: safeLength)
    }

    private static func utf16Suffix(_ text: String, from location: Int) -> String {
        let nsText = text as NSString
        let safeLocation = min(max(0, location), nsText.length)
        return nsText.substring(from: safeLocation)
    }

    func replaceFirstMatch(
        _ match: SearchMatch,
        with replacement: String,
        needle: String,
        caseSensitive: Bool,
        useRegex: Bool
    ) -> SearchMatch? {
        let line = self.line(at: match.lineIndex)
        let nsLine = line as NSString
        guard NSMaxRange(match.range) <= nsLine.length else { return nil }
        let newLine = nsLine.replacingCharacters(in: match.range, with: replacement)
        _ = replaceLines(in: match.lineIndex ..< match.lineIndex + 1, with: [newLine])
        return search(needle: needle, caseSensitive: caseSensitive, useRegex: useRegex)
            .first { candidate in
                candidate.lineIndex > match.lineIndex
                    || candidate.lineIndex == match.lineIndex && candidate.range.location >= match.range
                    .location + (replacement as NSString).length
            }
    }

    func replaceAllMatches(_ matches: [SearchMatch], with replacement: String) -> Int? {
        guard !matches.isEmpty else { return nil }
        var grouped: [Int: [NSRange]] = [:]
        for match in matches {
            grouped[match.lineIndex, default: []].append(match.range)
        }
        var earliestLine: Int?
        for lineIndex in grouped.keys.sorted().reversed() {
            guard let lineRanges = grouped[lineIndex] else { continue }
            let ranges = lineRanges.sorted { $0.location > $1.location }
            var nsLine = line(at: lineIndex) as NSString
            for range in ranges where NSMaxRange(range) <= nsLine.length {
                nsLine = nsLine.replacingCharacters(in: range, with: replacement) as NSString
            }
            _ = replaceLines(in: lineIndex ..< lineIndex + 1, with: [nsLine as String])
            earliestLine = min(earliestLine ?? lineIndex, lineIndex)
        }
        return earliestLine
    }

    struct SearchMatch {
        let lineIndex: Int
        let range: NSRange
    }

    func search(
        needle: String,
        caseSensitive: Bool,
        useRegex: Bool,
        maximumMatches: Int? = nil
    ) -> [SearchMatch] {
        guard !needle.isEmpty else { return [] }
        if let maximumMatches, maximumMatches <= 0 {
            return []
        }
        var matches: [SearchMatch] = []

        func reachedLimit() -> Bool {
            guard let maximumMatches else { return false }
            return matches.count >= maximumMatches
        }

        if useRegex {
            var options: NSRegularExpression.Options = [.anchorsMatchLines]
            if !caseSensitive {
                options.insert(.caseInsensitive)
            }
            guard let regex = try? NSRegularExpression(pattern: needle, options: options) else { return [] }

            for (lineIndex, line) in lines.enumerated() {
                if reachedLimit() {
                    break
                }
                let nsLine = line as NSString
                let lineRange = NSRange(location: 0, length: nsLine.length)
                regex.enumerateMatches(in: line, range: lineRange) { match, _, stop in
                    if reachedLimit() {
                        stop.pointee = true
                        return
                    }
                    guard let match, match.range.length > 0 else { return }
                    matches.append(SearchMatch(lineIndex: lineIndex, range: match.range))
                    if reachedLimit() {
                        stop.pointee = true
                    }
                }
            }
        } else {
            var options: NSString.CompareOptions = []
            if !caseSensitive {
                options.insert(.caseInsensitive)
            }

            for (lineIndex, line) in lines.enumerated() {
                if reachedLimit() {
                    break
                }
                let nsLine = line as NSString
                var searchRange = NSRange(location: 0, length: nsLine.length)
                while searchRange.location < nsLine.length, !reachedLimit() {
                    let found = nsLine.range(of: needle, options: options, range: searchRange)
                    guard found.location != NSNotFound else { break }
                    matches.append(SearchMatch(lineIndex: lineIndex, range: found))
                    searchRange.location = found.location + found.length
                    searchRange.length = nsLine.length - searchRange.location
                }
            }
        }

        return matches
    }

    private static func linesUTF16Length(_ lines: [String]) -> Int {
        lines.reduce(0) { $0 + $1.utf16.count }
    }

    private static func separatorCount(forLineCount count: Int) -> Int {
        max(0, count - 1)
    }
}
