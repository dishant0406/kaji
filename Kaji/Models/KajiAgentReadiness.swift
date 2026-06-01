enum KajiAgentReadiness: Equatable {
    case missingBun
    case missingRuntime
    case ready

    var isReady: Bool { self == .ready }

    var title: String {
        switch self {
        case .missingBun:
            "Bun required"
        case .missingRuntime:
            "Runtime missing"
        case .ready:
            "Ready"
        }
    }

    var detail: String {
        switch self {
        case .missingBun:
            "Install Bun 1.3.14 or newer, then restart Kaji."
        case .missingRuntime:
            "The Kaji Agent runtime was not found."
        case .ready:
            "Kaji Agent is ready."
        }
    }
}
