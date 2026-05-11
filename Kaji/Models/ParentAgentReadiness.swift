enum ParentAgentReadiness: Equatable {
    case disabled
    case missingNode
    case missingRuntime
    case ready

    var isReady: Bool { self == .ready }

    var title: String {
        switch self {
        case .disabled:
            "Disabled"
        case .missingNode:
            "Node.js required"
        case .missingRuntime:
            "Runtime missing"
        case .ready:
            "Ready"
        }
    }

    var detail: String {
        switch self {
        case .disabled:
            "Enable the parent agent to use Kaji's native orchestrator."
        case .missingNode:
            "Install Node.js, then restart Kaji. Recommended: brew install node"
        case .missingRuntime:
            "The Kaji parent-agent runtime was not found."
        case .ready:
            "Parent agent is enabled and ready."
        }
    }
}
