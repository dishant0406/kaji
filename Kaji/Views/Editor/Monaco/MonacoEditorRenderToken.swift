import Foundation

struct MonacoEditorRenderToken: Equatable {
    let editorID: UUID
    let filePath: String
    let backingStoreVersion: Int

    init(editorID: UUID, filePath: String, backingStoreVersion: Int) {
        self.editorID = editorID
        self.filePath = filePath
        self.backingStoreVersion = backingStoreVersion
    }

    init?(modelInput: MonacoEditorModelInput) {
        guard modelInput.hasBackingStore else { return nil }
        editorID = modelInput.editorID
        filePath = modelInput.filePath
        backingStoreVersion = modelInput.backingStoreVersion
    }
}

enum MonacoEditorRevealPolicy {
    static func shouldReveal(current: MonacoEditorRenderToken?, activated: MonacoEditorRenderToken?) -> Bool {
        guard let current, let activated else { return false }
        return current.editorID == activated.editorID && current.filePath == activated.filePath
    }

    static func hasExactActivation(current: MonacoEditorRenderToken?, activated: MonacoEditorRenderToken?) -> Bool {
        guard let current, let activated else { return false }
        return current == activated
    }
}
