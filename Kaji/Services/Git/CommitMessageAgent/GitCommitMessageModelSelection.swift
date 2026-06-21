import Foundation

struct GitCommitMessageModelSelector: Hashable {
    let providerID: String
    let modelID: String

    var rawValue: String { "\(providerID)/\(modelID)" }
    var label: String { "\(providerID) / \(modelID)" }

    init?(rawValue: String) {
        let value = Self.withoutThinkingSuffix(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let slash = value.firstIndex(of: "/") else { return nil }
        let provider = String(value[..<slash])
        let modelStart = value.index(after: slash)
        let model = String(value[modelStart...])
        guard !provider.isEmpty, !model.isEmpty else { return nil }
        providerID = provider
        modelID = model
    }

    init(providerID: String, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }

    private static func withoutThinkingSuffix(_ value: String) -> String {
        let suffixes = [":off", ":minimal", ":low", ":medium", ":high"]
        guard let suffix = suffixes.first(where: { value.hasSuffix($0) }) else { return value }
        return String(value.dropLast(suffix.count))
    }
}

enum GitCommitMessageModelSelection {
    static func recommendedSelector(
        currentSelector: String,
        modelOptions: [KajiAgentModelOption],
        modelRoles: [KajiAgentModelRoleAssignment]
    ) -> GitCommitMessageModelSelector? {
        if let current = GitCommitMessageModelSelector(rawValue: currentSelector), contains(current, in: modelOptions) {
            return current
        }
        for role in ["commit", "smol", "default"] {
            if let selector = modelRoles.first(where: { $0.role == role })?.selector,
               let parsed = GitCommitMessageModelSelector(rawValue: selector),
               contains(parsed, in: modelOptions)
            {
                return parsed
            }
        }
        guard let option = modelOptions.first else { return nil }
        return GitCommitMessageModelSelector(providerID: option.provider, modelID: option.modelID)
    }

    static func modelOptions(
        for providerID: String,
        currentSelector: String,
        modelOptions: [KajiAgentModelOption],
        modelRoles: [KajiAgentModelRoleAssignment]
    ) -> [KajiAgentModelOption] {
        let provider = providerID.isEmpty
            ? recommendedSelector(currentSelector: currentSelector, modelOptions: modelOptions, modelRoles: modelRoles)?.providerID
            : providerID
        guard let provider else { return [] }
        return modelOptions.filter { $0.provider == provider }
    }

    private static func contains(_ selector: GitCommitMessageModelSelector, in options: [KajiAgentModelOption]) -> Bool {
        options.contains { $0.provider == selector.providerID && $0.modelID == selector.modelID }
    }
}
