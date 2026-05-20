import Foundation

struct SwiftyDiffHunkHeader: Equatable {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
}

enum HunkHeaderParser {
    static func parse(_ line: String) -> SwiftyDiffHunkHeader? {
        let pattern = #"@@\s*-([0-9]+),?([0-9]*)\s*\+([0-9]+),?([0-9]*)\s*@@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        else { return nil }

        return SwiftyDiffHunkHeader(
            oldStart: intValue(in: line, match: match, rangeIndex: 1, defaultValue: 0),
            oldCount: intValue(in: line, match: match, rangeIndex: 2, defaultValue: 1),
            newStart: intValue(in: line, match: match, rangeIndex: 3, defaultValue: 0),
            newCount: intValue(in: line, match: match, rangeIndex: 4, defaultValue: 1)
        )
    }

    private static func intValue(
        in line: String,
        match: NSTextCheckingResult,
        rangeIndex: Int,
        defaultValue: Int
    ) -> Int {
        let range = match.range(at: rangeIndex)
        guard range.location != NSNotFound, range.length > 0 else { return defaultValue }
        return Int((line as NSString).substring(with: range)) ?? defaultValue
    }
}
