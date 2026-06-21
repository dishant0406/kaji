import Foundation
import Testing

@testable import Kaji

@Suite("Monaco editor reveal policy", .serialized)
struct MonacoEditorRevealPolicyTests {
    @Test("does not reveal before matching activation")
    func doesNotRevealBeforeMatchingActivation() {
        let current = MonacoEditorRenderToken(
            editorID: UUID(),
            filePath: "/tmp/project/App.swift",
            backingStoreVersion: 1
        )

        #expect(!MonacoEditorRevealPolicy.shouldReveal(current: current, activated: nil))
        #expect(!MonacoEditorRevealPolicy.shouldReveal(current: nil, activated: current))
    }

    @Test("reveals matching editor and file")
    func revealsMatchingEditorAndFile() {
        let editorID = UUID()
        let current = MonacoEditorRenderToken(
            editorID: editorID,
            filePath: "/tmp/project/App.swift",
            backingStoreVersion: 2
        )
        let activated = MonacoEditorRenderToken(
            editorID: editorID,
            filePath: "/tmp/project/App.swift",
            backingStoreVersion: 1
        )

        #expect(MonacoEditorRevealPolicy.shouldReveal(current: current, activated: activated))
        #expect(!MonacoEditorRevealPolicy.hasExactActivation(current: current, activated: activated))
    }

    @Test("does not reveal stale file or editor")
    func doesNotRevealStaleFileOrEditor() {
        let editorID = UUID()
        let current = MonacoEditorRenderToken(
            editorID: editorID,
            filePath: "/tmp/project/App.swift",
            backingStoreVersion: 1
        )

        #expect(!MonacoEditorRevealPolicy.shouldReveal(
            current: current,
            activated: MonacoEditorRenderToken(
                editorID: editorID,
                filePath: "/tmp/project/Other.swift",
                backingStoreVersion: 1
            )
        ))
        #expect(!MonacoEditorRevealPolicy.shouldReveal(
            current: current,
            activated: MonacoEditorRenderToken(
                editorID: UUID(),
                filePath: "/tmp/project/App.swift",
                backingStoreVersion: 1
            )
        ))
    }

    @Test("creates token only after backing store exists")
    @MainActor
    func createsTokenOnlyAfterBackingStoreExists() {
        let state = EditorTabState(projectPath: "/tmp/project", filePath: "/tmp/project/App.swift")
        #expect(MonacoEditorRenderToken(modelInput: MonacoEditorModelInput(state: state)) == nil)

        let store = TextBackingStore()
        store.loadFromText("let value = 1\n")
        state.backingStore = store
        state.backingStoreVersion = 1

        let token = MonacoEditorRenderToken(modelInput: MonacoEditorModelInput(state: state))
        #expect(token?.editorID == state.id)
        #expect(token?.filePath == state.filePath)
        #expect(token?.backingStoreVersion == 1)
    }
}
