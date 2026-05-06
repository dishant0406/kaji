import Foundation

enum NativeMarkdownSegmentKind: Hashable {
    case markdown
    case managedBlock(title: String)
}

struct NativeMarkdownSegment: Identifiable, Hashable {
    let id: Int
    let kind: NativeMarkdownSegmentKind
    let content: String
}

enum NativeMarkdownSegmenter {
    private static let markerPattern = #"<!--\s*(BEGIN|END)\s+([^>]+?)\s*-->"#

    static func segments(from content: String) -> [NativeMarkdownSegment] {
        var segments: [NativeMarkdownSegment] = []
        var searchStart = content.startIndex

        while let begin = nextMarker(in: content, range: searchStart..<content.endIndex, kind: "BEGIN") {
            appendMarkdown(content[searchStart..<begin.lowerBound], to: &segments)
            let blockStart = begin.upperBound
            guard let end = nextEndMarker(in: content, range: blockStart..<content.endIndex, title: begin.title) else {
                appendMarkdown(content[begin.lowerBound..<content.endIndex], to: &segments)
                return segments
            }
            appendManagedBlock(content[blockStart..<end.lowerBound], title: begin.title, to: &segments)
            searchStart = end.upperBound
        }

        appendMarkdown(content[searchStart..<content.endIndex], to: &segments)
        return segments.isEmpty ? [NativeMarkdownSegment(id: 0, kind: .markdown, content: content)] : segments
    }

    private static func appendMarkdown(_ value: Substring, to segments: inout [NativeMarkdownSegment]) {
        append(value, kind: .markdown, to: &segments)
    }

    private static func appendManagedBlock(_ value: Substring, title: String, to segments: inout [NativeMarkdownSegment]) {
        append(value, kind: .managedBlock(title: title), to: &segments)
    }

    private static func append(
        _ value: Substring,
        kind: NativeMarkdownSegmentKind,
        to segments: inout [NativeMarkdownSegment]
    ) {
        let content = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        segments.append(NativeMarkdownSegment(id: segments.count, kind: kind, content: content))
    }

    private static func nextEndMarker(in content: String, range: Range<String.Index>, title: String) -> Marker? {
        var searchStart = range.lowerBound
        while let marker = nextMarker(in: content, range: searchStart..<range.upperBound, kind: "END") {
            if marker.title == title { return marker }
            searchStart = marker.upperBound
        }
        return nil
    }

    private static func nextMarker(in content: String, range: Range<String.Index>, kind: String) -> Marker? {
        guard let regex = try? NSRegularExpression(pattern: markerPattern) else { return nil }
        let nsRange = NSRange(range, in: content)
        let matches = regex.matches(in: content, range: nsRange)
        for match in matches {
            guard match.numberOfRanges == 3,
                  let fullRange = Range(match.range(at: 0), in: content),
                  let kindRange = Range(match.range(at: 1), in: content),
                  let titleRange = Range(match.range(at: 2), in: content),
                  content[kindRange].uppercased() == kind
            else { continue }
            let title = String(content[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            return Marker(range: fullRange, title: title)
        }
        return nil
    }

    private struct Marker {
        let range: Range<String.Index>
        let title: String

        var lowerBound: String.Index { range.lowerBound }
        var upperBound: String.Index { range.upperBound }
    }
}
