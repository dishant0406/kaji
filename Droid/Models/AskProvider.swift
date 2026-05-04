import Foundation

struct AskProvider: Hashable, Identifiable {
    static let terminal = AskProvider(id: "terminal", title: "Terminal", annotationValue: "terminal", iconName: "terminal")
    static let codex = AskProvider(agentID: "codex")
    static let claude = AskProvider(agentID: "claude")
    static let opencode = AskProvider(agentID: "opencode")
    static let pi = AskProvider(agentID: "pi")

    let id: String
    let title: String
    let annotationValue: String
    let iconName: String

    var rawValue: String { id }
    var commandTitle: String { title }
    var launcherID: String? { self == .terminal ? nil : id }
    var definition: CodingAgentDefinition? { CodingAgentRegistry.shared.definition(id: id) }

    static var allCases: [AskProvider] {
        [.terminal] + CodingAgentRegistry.shared.definitions.map { AskProvider(definition: $0) }
    }

    init(id: String, title: String, annotationValue: String, iconName: String) {
        self.id = id
        self.title = title
        self.annotationValue = annotationValue
        self.iconName = iconName
    }

    init(definition: CodingAgentDefinition) {
        self.init(
            id: definition.id,
            title: definition.displayName,
            annotationValue: definition.annotationValues.first ?? definition.id,
            iconName: definition.iconName
        )
    }

    init(agentID: String) {
        if let definition = CodingAgentRegistry.shared.definition(id: agentID) {
            self.init(definition: definition)
        } else {
            self.init(id: agentID, title: agentID.capitalized, annotationValue: agentID, iconName: "sparkles")
        }
    }

    func matches(title: String) -> Bool {
        Self.detect(from: title) == self
    }

    static func detect(from title: String) -> Self {
        CodingAgentRegistry.shared.detect(title: title, startupCommand: nil, injectedCommand: nil, processNames: [])
            .map(AskProvider.init(definition:)) ?? .terminal
    }

    static func detect(
        title: String,
        startupCommand: String?,
        injectedCommand: String?,
        processNames: [String] = []
    ) -> Self {
        CodingAgentRegistry.shared.detect(
            title: title,
            startupCommand: startupCommand,
            injectedCommand: injectedCommand,
            processNames: processNames
        ).map(AskProvider.init(definition:)) ?? .terminal
    }

    static func resolveAnnotation(_ value: String) -> Self? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["terminal", "term", "shell"].contains(normalized) { return .terminal }
        return CodingAgentRegistry.shared.resolve(value).map(AskProvider.init(definition:))
    }
}
