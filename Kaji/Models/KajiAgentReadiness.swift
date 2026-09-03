enum KajiAgentReadiness: Equatable {
    case checking
    case missingRuntime
    case ready

    var isReady: Bool { self == .ready }

    var title: String {
        switch self {
        case .checking:
            "Checking KajiCode"
        case .missingRuntime:
            "KajiCode missing"
        case .ready:
            "Ready"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            "Checking for the KajiCode binary."
        case .missingRuntime:
            "Install KajiCode from Settings to enable runtime-backed features."
        case .ready:
            "KajiCode is ready."
        }
    }
}
