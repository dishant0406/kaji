enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case terminal = "Terminal"
    case cli = "Coding Agents"
    case aiGateway = "AI Gateway"
    case extensions = "Extensions"
    case agents = "Agents"
    case editor = "Editor"
    case speechToText = "Speech to Text"
    case shortcuts = "Shortcuts"
    case notifications = "Notifications"
    case aiUsage = "AI Usage"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .terminal: "terminal"
        case .cli: "terminal"
        case .aiGateway: "point.3.connected.trianglepath.dotted"
        case .extensions: "puzzlepiece.extension"
        case .agents: "rectangle.stack"
        case .editor: "pencil.line"
        case .speechToText: "mic"
        case .shortcuts: "keyboard"
        case .notifications: "bell"
        case .aiUsage: "chart.bar"
        }
    }
}
