enum KajiAgentReadiness: Equatable {
    case checking
    case missingBun
    case unsupportedBunVersion(String?)
    case missingRuntime
    case ready

    var isReady: Bool { self == .ready }

    var title: String {
        switch self {
        case .checking:
            "Checking runtime"
        case .missingBun:
            "Bun required"
        case .unsupportedBunVersion:
            "Update Bun"
        case .missingRuntime:
            "Runtime missing"
        case .ready:
            "Ready"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            "Checking Kaji Agent runtime and Bun."
        case .missingBun:
            "Install Bun 1.3.14 or newer, then retry Kaji Agent."
        case let .unsupportedBunVersion(version):
            if let version, !version.isEmpty {
                "Install Bun 1.3.14 or newer. Found Bun \(version)."
            } else {
                "Install Bun 1.3.14 or newer."
            }
        case .missingRuntime:
            "The Kaji Agent runtime is missing from the app bundle."
        case .ready:
            "Kaji Agent is ready."
        }
    }
}
