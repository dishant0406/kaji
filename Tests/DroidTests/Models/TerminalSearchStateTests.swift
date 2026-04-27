import Testing

@testable import Droid

@Suite("TerminalSearchState")
@MainActor
struct TerminalSearchStateTests {
    @Test("short queries wait before publishing")
    func shortQueryDelay() async throws {
        let state = TerminalSearchState()
        var values: [String] = []
        state.startPublishing { values.append($0) }

        state.needle = "ab"
        state.pushNeedle()

        try await Task.sleep(for: .milliseconds(150))
        #expect(values.isEmpty)

        try await Task.sleep(for: .milliseconds(250))
        #expect(values == ["ab"])
    }

    @Test("rapid long queries coalesce to the latest value")
    func longQueryCoalescing() async throws {
        let state = TerminalSearchState()
        var values: [String] = []
        state.startPublishing { values.append($0) }

        state.needle = "hel"
        state.pushNeedle()

        try await Task.sleep(for: .milliseconds(40))

        state.needle = "hello"
        state.pushNeedle()

        try await Task.sleep(for: .milliseconds(180))
        #expect(values == ["hello"])
    }
}
