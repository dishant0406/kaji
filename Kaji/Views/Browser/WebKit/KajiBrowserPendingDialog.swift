import Foundation

@MainActor
final class KajiBrowserPendingDialog {
    let id = UUID()
    let type: String
    let message: String
    let defaultText: String
    private let completion: (Bool, String?) -> Void
    private(set) var resolved = false

    init(type: String, message: String, defaultText: String = "", completion: @escaping (Bool, String?) -> Void) {
        self.type = type
        self.message = message
        self.defaultText = defaultText
        self.completion = completion
    }

    func resolve(accept: Bool, promptText: String?) {
        guard !resolved else { return }
        resolved = true
        completion(accept, promptText)
    }

    var payload: [String: Any] {
        [
            "id": id.uuidString,
            "type": type,
            "message": message,
            "defaultText": defaultText,
        ]
    }
}
