import Foundation

@MainActor
@Observable
final class InlineEditSettings {
    static let shared = InlineEditSettings()

    private let providerKey = "kaji.inlineEdit.provider"
    private let modelPrefix = "kaji.inlineEdit.model."

    var providerID: String {
        get { UserDefaults.standard.string(forKey: providerKey) ?? AskProvider.opencode.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: providerKey) }
    }

    func modelID(for providerID: String) -> String? {
        let value = UserDefaults.standard.string(forKey: modelPrefix + providerID) ?? ""
        return value.isEmpty ? nil : value
    }

    func setModelID(_ modelID: String?, for providerID: String) {
        let key = modelPrefix + providerID
        guard let modelID, !modelID.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(modelID, forKey: key)
    }
}
