import Foundation

struct AgentComposerSuggestion: Identifiable, Hashable {
    enum Kind: Hashable {
        case slash
        case file
        case promptAction
        case skill
        case history
    }

    let id: String
    let title: String
    let detail: String
    let annotation: String?
    let replacement: String?
    let kind: Kind
    var submitOnEnter = false
    var slashName: String?
    var opensNativePanel = false
}

struct AgentComposerCompletionState: Equatable {
    var triggerRange: Range<String.Index>?
    var suggestions: [AgentComposerSuggestion] = []
    var highlightedIndex = 0
    var inlineHint: String?

    var isVisible: Bool { !suggestions.isEmpty }

    mutating func clear() {
        triggerRange = nil
        suggestions = []
        highlightedIndex = 0
        inlineHint = nil
    }
}
