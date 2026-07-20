import Foundation

@MainActor
@Observable
final class GitCommitMessageSettingsStore {
    static let shared = GitCommitMessageSettingsStore()
    static let modelSelectorKey = "kaji.git.commitMessage.modelSelector"
    static let providerIDKey = "kaji.git.commitMessage.providerID"
    static let modelIDKey = "kaji.git.commitMessage.modelID"
    static let contextLevelKey = "kaji.git.commitMessage.contextLevel"
    static let customInstructionsKey = "kaji.git.commitMessage.customInstructions"

    private let defaults: UserDefaults

    var modelSelector: String {
        didSet {
            let normalized = Self.normalizedSelector(modelSelector)
            if modelSelector != normalized {
                modelSelector = normalized
                return
            }
            defaults.set(modelSelector, forKey: Self.modelSelectorKey)
        }
    }

    var contextLevel: String {
        didSet {
            if GitCommitMessageContextLevel(rawValue: contextLevel) == nil {
                contextLevel = GitCommitMessageContextLevel.fast.rawValue
            }
            defaults.set(contextLevel, forKey: Self.contextLevelKey)
        }
    }

    var customInstructions: String {
        didSet {
            defaults.set(customInstructions, forKey: Self.customInstructionsKey)
        }
    }

    var selectedContextLevel: GitCommitMessageContextLevel {
        GitCommitMessageContextLevel(rawValue: contextLevel) ?? .fast
    }

    var selectedSelector: GitCommitMessageModelSelector? {
        GitCommitMessageModelSelector(rawValue: modelSelector)
    }

    var selectedModelLabel: String {
        selectedSelector?.label ?? "Recommended commit role"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        modelSelector = Self.initialSelector(defaults: defaults)
        let storedContextLevel = defaults.string(forKey: Self.contextLevelKey)
            ?? GitCommitMessageContextLevel.fast.rawValue
        contextLevel = GitCommitMessageContextLevel(rawValue: storedContextLevel)?.rawValue
            ?? GitCommitMessageContextLevel.fast.rawValue
        customInstructions = defaults.string(forKey: Self.customInstructionsKey) ?? ""
    }

    func snapshot() -> GitCommitMessageSettingsSnapshot {
        let selector = selectedSelector
        return GitCommitMessageSettingsSnapshot(
            modelSelector: selector?.rawValue ?? "",
            providerID: selector?.providerID ?? "",
            modelID: selector?.modelID ?? "",
            contextLevel: selectedContextLevel,
            customInstructions: customInstructions
        )
    }

    private static func initialSelector(defaults: UserDefaults) -> String {
        if let selector = defaults.string(forKey: Self.modelSelectorKey) {
            return normalizedSelector(selector)
        }
        guard let provider = defaults.string(forKey: Self.providerIDKey),
              let model = defaults.string(forKey: Self.modelIDKey)
        else { return "" }
        return normalizedSelector("\(provider)/\(model)")
    }

    private static func normalizedSelector(_ value: String) -> String {
        GitCommitMessageModelSelector(rawValue: value)?.rawValue ?? ""
    }
}

struct GitCommitMessageSettingsSnapshot: Hashable {
    let modelSelector: String
    let providerID: String
    let modelID: String
    let contextLevel: GitCommitMessageContextLevel
    let customInstructions: String

    var modelLabel: String {
        GitCommitMessageModelSelector(rawValue: modelSelector)?.label ?? "Recommended commit role"
    }

    var trimmedInstructions: String {
        String(customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
    }
}
