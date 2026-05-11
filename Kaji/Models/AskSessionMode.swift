import Foundation

enum AskSessionMode: String, CaseIterable, Hashable, Identifiable {
    case bestMatch
    case existingSession
    case newTerminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestMatch:
            "Best Match"
        case .existingSession:
            "Existing Session"
        case .newTerminal:
            "New Terminal"
        }
    }

    var annotationValue: String {
        switch self {
        case .bestMatch:
            "best"
        case .existingSession:
            "existing"
        case .newTerminal:
            "new"
        }
    }

    static func resolveAnnotation(_ value: String) -> Self? {
        let normalized = value.lowercased()
        return allCases.first { mode in
            mode.annotationValue == normalized ||
                mode.rawValue.lowercased() == normalized ||
                (mode == .bestMatch && ["bestmatch", "best-match"].contains(normalized)) ||
                (mode == .existingSession && ["existing-session", "existingsession", "existing"].contains(normalized)) ||
                (mode == .newTerminal && ["newterminal", "new-terminal", "new"].contains(normalized))
        }
    }
}
