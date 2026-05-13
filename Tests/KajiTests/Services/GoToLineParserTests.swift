import Testing

@testable import Kaji

@Suite("GoToLineParser")
struct GoToLineParserTests {
    @Test("parses line only")
    func parsesLineOnly() {
        #expect(GoToLineParser.parse("42") == EditorLineNavigationRequest(line: 42, column: 1))
    }

    @Test("parses line and column")
    func parsesLineAndColumn() {
        #expect(GoToLineParser.parse("120:8") == EditorLineNavigationRequest(line: 120, column: 8))
    }

    @Test("invalid column falls back to first column")
    func invalidColumnFallback() {
        #expect(GoToLineParser.parse("12:nope") == EditorLineNavigationRequest(line: 12, column: 1))
    }

    @Test("rejects empty nonnumeric and zero lines")
    func rejectsInvalidLines() {
        #expect(GoToLineParser.parse("") == nil)
        #expect(GoToLineParser.parse("abc") == nil)
        #expect(GoToLineParser.parse("0") == nil)
    }
}
