import Foundation

@MainActor
@Observable
final class AskPrefillState {
    static let shared = AskPrefillState()

    var text = ""
    var version = 0

    func set(_ text: String) {
        self.text = text
        version += 1
    }

    func consume() -> String {
        defer { text = "" }
        return text
    }
}
