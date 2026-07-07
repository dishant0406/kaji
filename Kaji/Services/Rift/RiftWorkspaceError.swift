import Foundation

enum RiftWorkspaceError: LocalizedError {
    case binaryUnavailable
    case commandFailed(String)
    case emptyCreateOutput
    case missingRiftMarker(String)

    var errorDescription: String? {
        switch self {
        case .binaryUnavailable:
            "Bundled Rift binary is unavailable. Run scripts/setup.sh to install it."
        case let .commandFailed(message):
            message
        case .emptyCreateOutput:
            "Rift did not return a workspace path."
        case let .missingRiftMarker(path):
            "Rift marker is missing at \(path)."
        }
    }
}
