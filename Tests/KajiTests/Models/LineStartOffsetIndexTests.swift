import Foundation
import Testing

@testable import Kaji

@Suite("LineStartOffsetIndex")
struct LineStartOffsetIndexTests {
    @Test("builds utf16 line starts")
    func buildsOffsets() {
        #expect(LineStartOffsetIndex.offsets(in: "a\nbb\n") == [0, 2, 5])
        #expect(LineStartOffsetIndex.offsets(in: "😀\nx") == [0, 3])
    }

    @Test("returns line ranges from offsets without scanning content")
    func lineRangesFromOffsets() {
        let text = "a\n😀x\n"
        let offsets = LineStartOffsetIndex.offsets(in: text)
        let contentLength = (text as NSString).length

        #expect(LineStartOffsetIndex.lineRangeExcludingNewline(
            localLine: 0,
            offsets: offsets,
            contentLength: contentLength
        ) == NSRange(location: 0, length: 1))
        #expect(LineStartOffsetIndex.lineRangeExcludingNewline(
            localLine: 1,
            offsets: offsets,
            contentLength: contentLength
        ) == NSRange(location: 2, length: 3))
        #expect(LineStartOffsetIndex.lineRangeExcludingNewline(
            localLine: 2,
            offsets: offsets,
            contentLength: contentLength
        ) == NSRange(location: 6, length: 0))
        #expect(LineStartOffsetIndex.lineRangeExcludingNewline(
            localLine: 3,
            offsets: offsets,
            contentLength: contentLength
        ) == nil)
    }

    @Test("updates single middle line without rebuilding")
    func updatesMiddleLine() {
        let offsets = LineStartOffsetIndex.offsets(in: "aa\nbbb\nc")

        let updated = LineStartOffsetIndex.applyingReplacement(
            to: offsets,
            viewportStartLine: 10,
            globalStartLine: 11,
            oldLineCount: 1,
            newLines: ["b"]
        )

        #expect(updated == LineStartOffsetIndex.offsets(in: "aa\nb\nc"))
    }

    @Test("updates last line")
    func updatesLastLine() {
        let offsets = LineStartOffsetIndex.offsets(in: "aa\nbbb")

        let updated = LineStartOffsetIndex.applyingReplacement(
            to: offsets,
            viewportStartLine: 0,
            globalStartLine: 1,
            oldLineCount: 1,
            newLines: ["bbbb"]
        )

        #expect(updated == LineStartOffsetIndex.offsets(in: "aa\nbbbb"))
    }

    @Test("updates line split")
    func updatesLineSplit() {
        let offsets = LineStartOffsetIndex.offsets(in: "aa\nbbb\nc")

        let updated = LineStartOffsetIndex.applyingReplacement(
            to: offsets,
            viewportStartLine: 0,
            globalStartLine: 1,
            oldLineCount: 1,
            newLines: ["b", "bb"]
        )

        #expect(updated == LineStartOffsetIndex.offsets(in: "aa\nb\nbb\nc"))
    }
}
