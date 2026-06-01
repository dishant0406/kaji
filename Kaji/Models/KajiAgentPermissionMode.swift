enum KajiAgentPermissionMode: String, CaseIterable, Identifiable {
    case ask
    case readAllow = "read-allow"
    case bypass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask"
        case .readAllow: "Read allow"
        case .bypass: "Bypass"
        }
    }

    var detail: String {
        switch self {
        case .ask: "Ask before read, write, and exec tools."
        case .readAllow: "Allow read tools; ask for write and exec tools."
        case .bypass: "Allow all tools without prompts."
        }
    }
}
