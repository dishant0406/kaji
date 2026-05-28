import Foundation
import Testing

@testable import Kaji

@Suite("TabAreaContentIndex")
@MainActor
struct TabAreaContentIndexTests {
    private let projectPath = "/tmp/test"

    @Test("registers editor tabs by file path")
    func registersEditorTabsByFilePath() {
        let tab = TerminalTab(editorState: EditorTabState(projectPath: projectPath, filePath: "/tmp/test/file.swift"))
        let index = TabAreaContentIndex(tabs: [tab])

        #expect(index.editorTabID(filePath: "/tmp/test/file.swift") == tab.id)
    }

    @Test("unregister removes indexed tabs")
    func unregisterRemovesIndexedTabs() {
        let tab = TerminalTab(filePreviewState: FilePreviewTabState(
            projectPath: projectPath,
            filePath: "/tmp/test/image.png",
            kind: .image
        ))
        var index = TabAreaContentIndex(tabs: [tab])

        index.unregister(tab)

        #expect(index.filePreviewTabID(filePath: "/tmp/test/image.png") == nil)
    }

    @Test("registers external editor terminal tabs")
    func registersExternalEditorTerminalTabs() {
        let pane = TerminalPaneState(
            projectPath: projectPath,
            title: "vim file.swift",
            startupCommand: "vim /tmp/test/file.swift",
            externalEditorFilePath: "/tmp/test/file.swift"
        )
        let tab = TerminalTab(pane: pane)
        let index = TabAreaContentIndex(tabs: [tab])

        #expect(index.externalEditorTabID(filePath: "/tmp/test/file.swift") == tab.id)
    }

    @Test("registers one browser tab")
    func registersOneBrowserTab() {
        let tab = TerminalTab(browserState: BrowserPaneState(projectPath: projectPath, url: "https://example.com"))
        let index = TabAreaContentIndex(tabs: [tab])

        #expect(index.existingBrowserTabID() == tab.id)
    }
}
