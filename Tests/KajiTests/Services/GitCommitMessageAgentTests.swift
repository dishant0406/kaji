import Testing

@testable import Kaji

struct GitCommitMessageAgentTests {
    @MainActor
    @Test
    func sanitizeKeepsLastNonEmptyLine() {
        #expect(GitCommitMessageRuntimeClient.sanitize("  draft one  \n\n final message \n") == "final message")
    }

    @MainActor
    @Test
    func sanitizeStripsWrappingQuotes() {
        #expect(GitCommitMessageRuntimeClient.sanitize("\"quoted message\"") == "quoted message")
    }

    @MainActor
    @Test
    func sanitizeReturnsEmptyForBlankOutput() {
        #expect(GitCommitMessageRuntimeClient.sanitize("   \n  ") == "")
    }

    @MainActor
    @Test
    func sanitizeReturnsEmptyForEmptyOutput() {
        #expect(GitCommitMessageRuntimeClient.sanitize("") == "")
    }
}
