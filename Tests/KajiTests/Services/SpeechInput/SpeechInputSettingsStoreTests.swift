import Foundation
import Testing

@testable import Kaji

@Suite("Speech input settings store")
@MainActor
struct SpeechInputSettingsStoreTests {
    @Test("defaults persist after update")
    func defaultsPersistAfterUpdate() throws {
        let url = tempURL()
        let store = SpeechInputSettingsStore(fileURL: url)
        store.update { settings in
            settings.isEnabled = true
            settings.selectedModelID = "parakeet-eou-160ms"
        }
        let reloaded = SpeechInputSettingsStore(fileURL: url)
        #expect(reloaded.settings.isEnabled)
        #expect(reloaded.settings.selectedModelID == "parakeet-eou-160ms")
    }

    private func tempURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechInputSettingsStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }
}
