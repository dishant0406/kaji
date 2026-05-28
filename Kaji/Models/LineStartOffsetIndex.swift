import Foundation

enum LineStartOffsetIndex {
    static func offsets(in text: String) -> [Int] {
        let content = text as NSString
        var offsets = [0]
        var searchRange = NSRange(location: 0, length: content.length)
        while searchRange.location < content.length {
            let found = content.range(of: "\n", options: [], range: searchRange)
            guard found.location != NSNotFound else { break }
            let next = found.location + found.length
            if next <= content.length {
                offsets.append(next)
            }
            searchRange.location = next
            searchRange.length = content.length - next
        }
        return offsets
    }

    static func lineRangeExcludingNewline(
        localLine: Int,
        offsets: [Int],
        contentLength: Int
    ) -> NSRange? {
        guard localLine >= 0, localLine < offsets.count else { return nil }
        let location = min(max(0, offsets[localLine]), contentLength)
        let nextLocation = if localLine + 1 < offsets.count {
            min(max(location, offsets[localLine + 1]), contentLength)
        } else {
            contentLength
        }
        let rawLength = max(0, nextLocation - location)
        let excludesNewline = localLine + 1 < offsets.count ? max(0, rawLength - 1) : rawLength
        return NSRange(location: location, length: excludesNewline)
    }

    static func applyingReplacement(
        to offsets: [Int],
        viewportStartLine: Int,
        globalStartLine: Int,
        oldLineCount: Int,
        newLines: [String]
    ) -> [Int]? {
        guard oldLineCount > 0, !newLines.isEmpty else { return nil }
        let localStart = globalStartLine - viewportStartLine
        guard localStart >= 0, localStart < offsets.count else { return nil }
        let suffixStart = localStart + oldLineCount
        guard suffixStart <= offsets.count else { return nil }

        let baseOffset = offsets[localStart]
        let prefix = offsets[..<localStart]
        let replacementOffsets = replacementOffsets(baseOffset: baseOffset, lines: newLines)
        guard suffixStart < offsets.count else {
            return Array(prefix) + replacementOffsets
        }

        let oldSpan = offsets[suffixStart] - baseOffset
        let delta = replacementSpan(lines: newLines) - oldSpan
        let suffix = offsets[suffixStart...].map { $0 + delta }
        return Array(prefix) + replacementOffsets + suffix
    }

    private static func replacementOffsets(baseOffset: Int, lines: [String]) -> [Int] {
        var nextOffset = baseOffset
        return lines.map { line in
            defer { nextOffset += line.utf16.count + 1 }
            return nextOffset
        }
    }

    private static func replacementSpan(lines: [String]) -> Int {
        lines.reduce(0) { $0 + $1.utf16.count + 1 }
    }
}
