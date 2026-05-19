import Foundation
import Testing

@testable import Kaji

@Suite("LSP diagnostics")
struct LSPDiagnosticMapperTests {
    @Test("maps publish diagnostics to editor diagnostics")
    func mapsDiagnostics() {
        let params = LSPPublishDiagnosticsParams(
            uri: URL(fileURLWithPath: "/tmp/project/Sources/App.swift").absoluteString,
            diagnostics: [
                LSPDiagnostic(
                    range: LSPRange(start: LSPPosition(line: 4, character: 2), end: LSPPosition(line: 4, character: 8)),
                    severity: 1,
                    source: "sourcekit",
                    message: "Expected expression"
                ),
            ]
        )

        let diagnostics = LSPDiagnosticMapper.editorDiagnostics(
            params: params,
            projectPath: "/tmp/project",
            fallbackSource: "fallback"
        )

        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].relativePath == "Sources/App.swift")
        #expect(diagnostics[0].line == 5)
        #expect(diagnostics[0].column == 3)
        #expect(diagnostics[0].severity == .error)
        #expect(diagnostics[0].source == "sourcekit")
    }

    @Test("frames and extracts LSP messages")
    func messageFraming() throws {
        let payload = Data(#"{"jsonrpc":"2.0","method":"initialized","params":{}}"#.utf8)
        var buffer = LSPMessageFramer.frame(payload)

        let messages = LSPMessageFramer.extractMessages(from: &buffer)

        #expect(messages == [payload])
        #expect(buffer.isEmpty)
    }
}
