import AppKit
import Foundation

struct SpeechInputSettings: Codable, Equatable {
    var isEnabled: Bool
    var holdHotkey: KeyCombo
    var selectedModelID: String
    var keepModelWarm: Bool
    var insertTrailingSpace: Bool

    static let defaults = SpeechInputSettings(
        isEnabled: false,
        holdHotkey: KeyCombo(key: KeyCombo.spaceKey, command: true, shift: true),
        selectedModelID: SpeechInputModel.defaultID,
        keepModelWarm: false,
        insertTrailingSpace: true
    )

    func selectedModel(in models: [SpeechInputModel]) -> SpeechInputModel {
        models.first { $0.id == selectedModelID } ?? models.first { $0.id == SpeechInputModel.defaultID } ?? models[0]
    }
}
