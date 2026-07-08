import Foundation

enum AIGatewayRuntimeStatus: Equatable {
    case notInstalled
    case stopped
    case starting
    case running(String)
    case failed(String)

    var label: String {
        switch self {
        case .notInstalled: "Not installed"
        case .stopped: "Stopped"
        case .starting: "Starting"
        case let .running(endpoint): "Running at \(endpoint)"
        case let .failed(message): message
        }
    }
}
