import Foundation

@MainActor
@Observable
final class SpeechInputSettingsStore {
    static let shared = SpeechInputSettingsStore()

    var settings: SpeechInputSettings

    @ObservationIgnored private let store: CodableFileStore<SpeechInputSettings>

    init(fileURL: URL = KajiFileStorage.fileURL(filename: "speech-input-settings.json")) {
        store = CodableFileStore(fileURL: fileURL, options: .prettySorted)
        settings = (try? store.load()) ?? .defaults
    }

    func update(_ transform: (inout SpeechInputSettings) -> Void) {
        var next = settings
        transform(&next)
        settings = next
        save()
    }

    func reset() {
        settings = .defaults
        save()
    }

    private func save() {
        do {
            try store.save(settings)
        } catch {
            DebugFileLog.logError("SpeechInput", error, context: "settings save failed")
        }
    }
}
