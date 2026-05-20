import Testing

@testable import Kaji

@Suite("SwiftyDiffAdapter parsing")
struct SwiftyDiffAdapterParsingTests {
    @Test("parseRows with empty string returns empty result")
    func parseRowsEmpty() {
        let result = SwiftyDiffAdapter.parseRows("")
        #expect(result.rows.isEmpty)
        #expect(result.additions == 0)
        #expect(result.deletions == 0)
    }

    @Test("parseRows skips file metadata before first hunk")
    func parseRowsSkipsFileMetadata() {
        let patch = """
        diff --git a/file.swift b/file.swift
        index abc..def 100644
        --- a/file.swift
        +++ b/file.swift
        @@ -1,3 +1,3 @@
         context
        -old
        +new
        """
        let result = SwiftyDiffAdapter.parseRows(patch)
        #expect(result.rows.count == 4)
        #expect(result.rows[0].kind == .hunk)
    }

    @Test("parseRows with single hunk parses all row kinds")
    func parseRowsSingleHunk() {
        let patch = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -10,4 +10,4 @@
         context line
        -deleted line
        +added line
         more context
        """
        let result = SwiftyDiffAdapter.parseRows(patch)

        #expect(result.rows.count == 5)
        #expect(result.rows[0].kind == .hunk)
        #expect(result.rows[1].kind == .context)
        #expect(result.rows[1].oldLineNumber == 10)
        #expect(result.rows[1].newLineNumber == 10)
        #expect(result.rows[2].kind == .deletion)
        #expect(result.rows[2].oldLineNumber == 11)
        #expect(result.rows[2].newLineNumber == nil)
        #expect(result.rows[3].kind == .addition)
        #expect(result.rows[3].oldLineNumber == nil)
        #expect(result.rows[3].newLineNumber == 11)
        #expect(result.rows[4].kind == .context)
        #expect(result.rows[4].oldLineNumber == 12)
        #expect(result.rows[4].newLineNumber == 12)
        #expect(result.additions == 1)
        #expect(result.deletions == 1)
    }

    @Test("parseRows additions only")
    func parseRowsAdditionsOnly() {
        let patch = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -5,2 +5,4 @@
         existing
        +new1
        +new2
         existing2
        """
        let result = SwiftyDiffAdapter.parseRows(patch)
        #expect(result.additions == 2)
        #expect(result.deletions == 0)

        let additions = result.rows.filter { $0.kind == .addition }
        #expect(additions.count == 2)
        #expect(additions[0].newLineNumber == 6)
        #expect(additions[1].newLineNumber == 7)
    }

    @Test("parseRows deletions only")
    func parseRowsDeletionsOnly() {
        let patch = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -5,4 +5,2 @@
         existing
        -removed1
        -removed2
         existing2
        """
        let result = SwiftyDiffAdapter.parseRows(patch)
        #expect(result.additions == 0)
        #expect(result.deletions == 2)

        let deletions = result.rows.filter { $0.kind == .deletion }
        #expect(deletions.count == 2)
        #expect(deletions[0].oldLineNumber == 6)
        #expect(deletions[1].oldLineNumber == 7)
    }

    @Test("parseRows with multiple hunks resets line numbers")
    func parseRowsMultipleHunks() {
        let patch = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1,3 +1,3 @@
         a
        -b
        +c
        @@ -20,3 +20,3 @@
         x
        -y
        +z
        """
        let result = SwiftyDiffAdapter.parseRows(patch)

        let hunks = result.rows.filter { $0.kind == .hunk }
        #expect(hunks.count == 2)
        #expect(result.rows.filter { $0.kind == .deletion }[1].oldLineNumber == 21)
        #expect(result.rows.filter { $0.kind == .addition }[1].newLineNumber == 21)
    }

    @Test("parseRows captures text content correctly")
    func parseRowsTextContent() {
        let patch = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1,3 +1,3 @@
         context
        -old
        +new
        """
        let result = SwiftyDiffAdapter.parseRows(patch)

        #expect(result.rows[1].text == " context")
        #expect(result.rows[1].oldText == "context")
        #expect(result.rows[1].newText == "context")
        #expect(result.rows[2].text == "-old")
        #expect(result.rows[2].oldText == "old")
        #expect(result.rows[2].newText == nil)
        #expect(result.rows[3].text == "+new")
        #expect(result.rows[3].oldText == nil)
        #expect(result.rows[3].newText == "new")
    }
}
