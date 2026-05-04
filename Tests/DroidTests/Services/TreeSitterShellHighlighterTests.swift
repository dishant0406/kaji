import Foundation
import Testing

@testable import Droid

struct TreeSitterShellHighlighterTests {
    @Test
    func highlightsShellScriptScopes() {
        let source = """
        # comment
        if [ -n "$HOME" ]; then
          echo "hello"
        fi
        """

        let scopes = Set(TreeSitterShellHighlighter.spans(in: source).map(\.scope))

        #expect(scopes.contains(.comment))
        #expect(scopes.contains(.keyword))
        #expect(scopes.contains(.string))
        #expect(scopes.contains(.function))
    }
}
