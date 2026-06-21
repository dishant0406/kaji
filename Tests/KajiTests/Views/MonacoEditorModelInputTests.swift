import Foundation
import Testing

@testable import Kaji

@Suite("Monaco editor model input", .serialized)
@MainActor
struct MonacoEditorModelInputTests {
    @Test("captures unloaded and loaded state changes")
    func capturesLoadedStateChanges() {
        let state = EditorTabState(projectPath: "/tmp/project", filePath: "/tmp/project/App.swift")
        let unloaded = MonacoEditorModelInput(state: state)

        let store = TextBackingStore()
        store.loadFromText("let value = 1\n")
        state.backingStore = store
        state.backingStoreVersion += 1
        state.isReadOnly = true

        let loaded = MonacoEditorModelInput(state: state)

        #expect(unloaded.editorID == loaded.editorID)
        #expect(!unloaded.hasBackingStore)
        #expect(loaded.hasBackingStore)
        #expect(loaded.backingStoreVersion == 1)
        #expect(loaded.isReadOnly)
        #expect(unloaded != loaded)
    }

    @Test("changes when sync relevant fields change")
    func changesWhenSyncFieldsChange() {
        let editorID = UUID()
        let base = MonacoEditorModelInput(
            editorID: editorID,
            filePath: "/tmp/project/App.swift",
            backingStoreVersion: 1,
            isReadOnly: false,
            hasBackingStore: true
        )

        #expect(base != MonacoEditorModelInput(
            editorID: editorID,
            filePath: "/tmp/project/Other.swift",
            backingStoreVersion: 1,
            isReadOnly: false,
            hasBackingStore: true
        ))
        #expect(base != MonacoEditorModelInput(
            editorID: editorID,
            filePath: "/tmp/project/App.swift",
            backingStoreVersion: 2,
            isReadOnly: false,
            hasBackingStore: true
        ))
        #expect(base != MonacoEditorModelInput(
            editorID: editorID,
            filePath: "/tmp/project/App.swift",
            backingStoreVersion: 1,
            isReadOnly: true,
            hasBackingStore: true
        ))
        #expect(base != MonacoEditorModelInput(
            editorID: editorID,
            filePath: "/tmp/project/App.swift",
            backingStoreVersion: 1,
            isReadOnly: false,
            hasBackingStore: false
        ))
    }
}
