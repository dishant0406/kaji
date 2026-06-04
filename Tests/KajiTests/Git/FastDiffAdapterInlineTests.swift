import Testing

@testable import Kaji

@Suite("Fast diff adapter inline pairing")
struct FastDiffAdapterInlineTests {
    @Test("parseRows attaches inline segments to similar replaced lines")
    func inlineSegmentsForSimilarReplacement() {
        let patch = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1,3 +1,3 @@
         context
        -let color = "red"
        +let color = "blue"
         tail
        """

        let result = SwiftyDiffAdapter.parseRows(patch)
        let deletion = result.rows.first { $0.kind == .deletion }
        let addition = result.rows.first { $0.kind == .addition }

        #expect(deletion?.oldInlineSegments?.contains { $0.emphasized && $0.text.contains("red") } == true)
        #expect(addition?.newInlineSegments?.contains { $0.emphasized && $0.text.contains("blue") } == true)
    }

    @Test("parseRows avoids noisy inline segments for unrelated replacements")
    func noInlineSegmentsForUnrelatedReplacement() {
        let patch = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1,2 +1,2 @@
        -alpha beta gamma
        +one two three
         tail
        """

        let result = SwiftyDiffAdapter.parseRows(patch)
        let deletion = result.rows.first { $0.kind == .deletion }
        let addition = result.rows.first { $0.kind == .addition }

        #expect(deletion?.oldInlineSegments == nil)
        #expect(addition?.newInlineSegments == nil)
    }

    @Test("parseRows skips no newline markers without changing line numbers")
    func skipsNoNewlineMarker() {
        let patch = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1 +1 @@
        -old
        \\ No newline at end of file
        +new
        \\ No newline at end of file
        """

        let result = SwiftyDiffAdapter.parseRows(patch)
        #expect(result.rows.filter { $0.kind == .deletion }.count == 1)
        #expect(result.rows.filter { $0.kind == .addition }.count == 1)
        #expect(result.additions == 1)
        #expect(result.deletions == 1)
    }

    @Test("parseRows skips inline segments for oversized replacement lines")
    func skipsInlineSegmentsForOversizedLines() {
        let oldLine = "let value = " + String(repeating: "a", count: 2100)
        let newLine = "let value = " + String(repeating: "b", count: 2100)
        let patch = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1 +1 @@
        -\(oldLine)
        +\(newLine)
        """

        let result = SwiftyDiffAdapter.parseRows(patch)
        let deletion = result.rows.first { $0.kind == .deletion }
        let addition = result.rows.first { $0.kind == .addition }

        #expect(deletion?.oldInlineSegments == nil)
        #expect(addition?.newInlineSegments == nil)
    }
}
