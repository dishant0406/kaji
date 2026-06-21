import Foundation

struct MonacoEditorModelInput: Equatable {
    let editorID: UUID
    let filePath: String
    let backingStoreVersion: Int
    let isReadOnly: Bool
    let hasBackingStore: Bool

    @MainActor
    init(state: EditorTabState) {
        editorID = state.id
        filePath = state.filePath
        backingStoreVersion = state.backingStoreVersion
        isReadOnly = state.isReadOnly
        hasBackingStore = state.backingStore != nil
    }

    init(
        editorID: UUID,
        filePath: String,
        backingStoreVersion: Int,
        isReadOnly: Bool,
        hasBackingStore: Bool
    ) {
        self.editorID = editorID
        self.filePath = filePath
        self.backingStoreVersion = backingStoreVersion
        self.isReadOnly = isReadOnly
        self.hasBackingStore = hasBackingStore
    }
}
