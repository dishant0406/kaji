import Foundation
import Testing

@testable import Kaji

@Suite("EditorTabState")
@MainActor
struct EditorTabStateTests {
    @Test("markdown tabs enable split scroll sync by default")
    func markdownTabsEnableSplitScrollSyncByDefault() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("notes.md")
        try "# Hello\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let state = EditorTabState(projectPath: tempDirectory.path, filePath: fileURL.path)

        #expect(state.isMarkdownFile)
        #expect(state.markdownViewMode == .preview)
        #expect(state.markdownScrollSyncEnabled)
    }

    @Test("editor tabs defer file loading until requested")
    func editorTabsDeferFileLoadingUntilRequested() throws {
        let (directory, fileURL) = try makeEditorFixture(name: "deferred.swift", content: "let value = 1\n")
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = EditorTabState(projectPath: directory.path, filePath: fileURL.path)

        #expect(!state.isLoading)
        #expect(!state.isIncrementalLoading)
        #expect(state.backingStore == nil)
    }

    @Test("editor tabs defer syntax highlighter creation until rendering")
    func editorTabsDeferSyntaxHighlighterCreation() throws {
        let (directory, fileURL) = try makeEditorFixture(name: "deferred.swift", content: "let value = 1\n")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = EditorTabState(projectPath: directory.path, filePath: fileURL.path)

        #expect(state.syntaxHighlighter == nil)

        _ = state.ensureSyntaxHighlighter()

        #expect(state.syntaxHighlighter != nil)
    }

    @Test("file path changes reset deferred syntax highlighter")
    func filePathChangesResetDeferredSyntaxHighlighter() throws {
        let (directory, fileURL) = try makeEditorFixture(name: "deferred.swift", content: "let value = 1\n")
        let nextFileURL = directory.appendingPathComponent("plain.unknown")
        try "plain\n".write(to: nextFileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = EditorTabState(projectPath: directory.path, filePath: fileURL.path)

        _ = state.ensureSyntaxHighlighter()
        state.updateFilePath(nextFileURL.path)

        #expect(state.syntaxHighlighter == nil)
        #expect(state.ensureSyntaxHighlighter() == nil)
    }

    @Test("loadIfNeeded starts loading only once")
    func loadIfNeededStartsLoadingOnlyOnce() async throws {
        let (directory, fileURL) = try makeEditorFixture(name: "load.swift", content: "let value = 1\n")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = EditorTabState(projectPath: directory.path, filePath: fileURL.path)

        state.loadIfNeeded()
        try await waitForLoad(state)
        let loadedVersion = state.backingStoreVersion

        state.loadIfNeeded()
        try await Task.sleep(for: .milliseconds(20))

        #expect(state.backingStore?.fullText() == "let value = 1\n")
        #expect(state.backingStoreVersion == loadedVersion)
    }

    @Test("inactive loads are cancelled before hidden editor tabs keep streaming")
    func inactiveLoadsAreCancelled() throws {
        let content = String(repeating: "let value = 1\n", count: 1000)
        let (directory, fileURL) = try makeEditorFixture(name: "cancel.swift", content: content)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = EditorTabState(projectPath: directory.path, filePath: fileURL.path)

        state.loadIfNeeded()
        state.suspendInactiveLoad()

        #expect(!state.isLoading)
        #expect(!state.isIncrementalLoading)
        #expect(state.backingStore == nil)
    }

    @Test("large clean inactive editors release backing store")
    func largeCleanInactiveEditorsReleaseBackingStore() throws {
        let (directory, fileURL) = try makeEditorFixture(name: "large.swift", content: "")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = EditorTabState(projectPath: directory.path, filePath: fileURL.path)
        let store = TextBackingStore()
        store.loadFromText(String(repeating: "let value = 1\n", count: 100_000))
        state.backingStore = store
        state.backingStoreVersion = 1

        state.suspendInactiveLoad()

        #expect(state.backingStore == nil)
        #expect(!state.isLoading)
        #expect(!state.isIncrementalLoading)
    }

    @Test("small clean inactive editors keep backing store")
    func smallCleanInactiveEditorsKeepBackingStore() throws {
        let (directory, fileURL) = try makeEditorFixture(name: "small.swift", content: "")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = EditorTabState(projectPath: directory.path, filePath: fileURL.path)
        let store = TextBackingStore()
        store.loadFromText("let value = 1\n")
        state.backingStore = store
        state.backingStoreVersion = 1

        state.suspendInactiveLoad()

        #expect(state.backingStore === store)
    }

    @Test("modified inactive editors keep backing store")
    func modifiedInactiveEditorsKeepBackingStore() throws {
        let (directory, fileURL) = try makeEditorFixture(name: "modified.swift", content: "")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = EditorTabState(projectPath: directory.path, filePath: fileURL.path)
        let store = TextBackingStore()
        store.loadFromText(String(repeating: "let value = 1\n", count: 100_000))
        state.backingStore = store
        state.backingStoreVersion = 1
        state.markModified()

        state.suspendInactiveLoad()

        #expect(state.backingStore === store)
    }

    @Test("large files skip document-wide markdown and symbol scans")
    func largeFilesSkipDocumentWideScans() throws {
        let (directory, fileURL) = try makeEditorFixture(name: "large.md", content: "")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = EditorTabState(projectPath: directory.path, filePath: fileURL.path)
        let store = TextBackingStore()
        store.loadFromText("# Title\n" + String(repeating: "content\n", count: 150_000))
        state.backingStore = store
        state.backingStoreVersion = 1

        #expect(!EditorStructuralAnalysisPolicy.allowsDocumentWideScan(store))
        #expect(state.markdownSyncAnchors().isEmpty)
        #expect(state.symbols().isEmpty)
    }

    @Test("large markdown files switch back to code mode")
    func largeMarkdownFilesSwitchBackToCodeMode() throws {
        let (directory, fileURL) = try makeEditorFixture(name: "large.md", content: "")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = EditorTabState(projectPath: directory.path, filePath: fileURL.path)
        let store = TextBackingStore()
        store.loadFromText("# Title\n" + String(repeating: "content\n", count: 150_000))
        state.backingStore = store
        state.backingStoreVersion = 1
        state.markdownViewMode = .preview
        state.markdownScrollSyncEnabled = true

        state.enforceMarkdownPreviewPolicy()

        #expect(!state.isMarkdownPreviewAvailable)
        #expect(state.markdownViewMode == .code)
        #expect(!state.markdownScrollSyncEnabled)
    }

    @Test("small markdown files keep preview mode")
    func smallMarkdownFilesKeepPreviewMode() throws {
        let (directory, fileURL) = try makeEditorFixture(name: "small.md", content: "")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = EditorTabState(projectPath: directory.path, filePath: fileURL.path)
        let store = TextBackingStore()
        store.loadFromText("# Title\ncontent\n")
        state.backingStore = store
        state.backingStoreVersion = 1
        state.markdownViewMode = .preview

        state.enforceMarkdownPreviewPolicy()

        #expect(state.isMarkdownPreviewAvailable)
        #expect(state.markdownViewMode == .preview)
    }

    @Test("cursor updates clamp invalid positions")
    func cursorUpdatesClampInvalidPositions() throws {
        let (directory, fileURL) = try makeEditorFixture(name: "cursor.swift", content: "")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = EditorTabState(projectPath: directory.path, filePath: fileURL.path)

        state.updateCursorPosition(line: -10, column: 0, selectionLength: -4)

        #expect(state.cursorPosition == EditorCursorPosition(line: 1, column: 1, selectionLength: 0))
    }

    private func makeEditorFixture(name: String, content: String) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return (directory, fileURL)
    }

    private func waitForLoad(_ state: EditorTabState) async throws {
        for _ in 0 ..< 100 {
            if state.backingStore != nil, !state.isLoading, !state.isIncrementalLoading { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for editor load")
    }
}
