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
            "Enable the parent agent to use Droid's native orchestrator."
        case .missingNode:
            "Install Node.js, then restart Droid. Recommended: brew install node"
        case .missingRuntime:
            "The Droid parent-agent runtime was not found."
        case .ready:
            "Parent agent is enabled and ready."
        }
    }
}
