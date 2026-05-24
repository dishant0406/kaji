import Foundation

@MainActor
@Observable
final class GitCommitMessageSettingsStore {
    static let shared = GitCommitMessageSettingsStore()
    static let contextLevelKey = "kaji.git.commitMessage.contextLevel"
    static let customInstructionsKey = "kaji.git.commitMessage.customInstructions"

    private let defaults: UserDefaults

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedContextLevel = defaults.string(forKey: Self.contextLevelKey)
            ?? GitCommitMessageContextLevel.fast.rawValue
        contextLevel = GitCommitMessageContextLevel(rawValue: storedContextLevel)?.rawValue
            ?? GitCommitMessageContextLevel.fast.rawValue
        customInstructions = defaults.string(forKey: Self.customInstructionsKey) ?? ""
    }

    func snapshot() -> GitCommitMessageSettingsSnapshot {
        GitCommitMessageSettingsSnapshot(
            contextLevel: selectedContextLevel,
            customInstructions: customInstructions
        )
    }
}

struct GitCommitMessageSettingsSnapshot: Hashable {
    let contextLevel: GitCommitMessageContextLevel
    let customInstructions: String

    var trimmedInstructions: String {
        String(customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
    }
}
