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
}
