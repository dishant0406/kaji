import Foundation

enum SpeechInputStatus: Equatable {
    case idle
    case requestingPermission
    case listening
    case transcribing
    case downloading(SpeechDownloadProgress)
    case preparing(SpeechDownloadProgress?)
    case error(String)

    var title: String {
        switch self {
        case .idle: "Ready"
        case .requestingPermission: "Requesting microphone"
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case let .downloading(progress): "Downloading model · \(progress.percentTitle)"
        case let .preparing(progress): "Preparing model · \(progress?.percentTitle ?? "0%")"
        case let .error(message): message
        }
    }

    var progress: SpeechDownloadProgress? {
        switch self {
        case let .downloading(progress): progress
        case let .preparing(progress): progress
        default: nil
        }
    }

    var isActive: Bool {
        switch self {
        case .listening,
             .transcribing,
             .downloading,
             .preparing,
             .requestingPermission: true
        case .idle,
             .error: false
        }
    }

    var allowsModelActions: Bool {
        switch self {
        case .idle,
             .error: true
        default: false
        }
    }
}
