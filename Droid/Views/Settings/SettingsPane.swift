enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case cli = "Coding Agents"
    case extensions = "Extensions"
    case agents = "Agents"
    case editor = "Editor"
    case shortcuts = "Shortcuts"
    case notifications = "Notifications"
    case aiUsage = "AI Usage"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .cli: "terminal"
        case .extensions: "puzzlepiece.extension"
        case .agents: "rectangle.stack"
        case .editor: "pencil.line"
        case .shortcuts: "keyboard"
        case .notifications: "bell"
        case .aiUsage: "chart.bar"
        }
    }
}
