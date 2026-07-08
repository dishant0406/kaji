import Foundation

enum AIGatewayInstallState: Equatable {
    case missing
    case installed
    case needsRepair(String)
}

struct AIGatewayInstallResult: Equatable {
    let state: AIGatewayInstallState
    let message: String
}
