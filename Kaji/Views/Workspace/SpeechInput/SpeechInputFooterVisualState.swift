import Foundation

enum SpeechInputFooterVisualState: Equatable {
    case disabled
    case ready
    case requestingPermission
    case listening
    case transcribing
    case downloading(SpeechDownloadProgress)
    case preparing(SpeechDownloadProgress?)
    case failed(String)

    static func resolve(status: SpeechInputStatus, isEnabled: Bool) -> SpeechInputFooterVisualState {
        switch status {
        case .idle:
            isEnabled ? .ready : .disabled
        case .requestingPermission:
            .requestingPermission
        case .listening:
            .listening
        case .transcribing:
            .transcribing
        case let .downloading(progress):
            .downloading(progress)
        case let .preparing(progress):
            .preparing(progress)
        case let .error(message):
            .failed(message)
        }
    }

    var isActive: Bool {
        switch self {
        case .requestingPermission,
             .listening,
             .transcribing,
             .downloading,
             .preparing: true
        case .disabled,
             .ready,
             .failed: false
        }
    }

    var isFailed: Bool {
        errorMessage != nil
    }

    var errorMessage: String? {
        if case let .failed(message) = self { return message }
        return nil
    }

    var progress: SpeechDownloadProgress? {
        switch self {
        case let .downloading(progress):
            progress
        case let .preparing(progress):
            progress
        default:
            nil
        }
    }

    var accessibilityValue: String {
        switch self {
        case .disabled:
            "Disabled"
        case .ready:
            "Ready"
        case .requestingPermission:
            "Requesting microphone permission"
        case .listening:
            "Listening"
        case .transcribing:
            "Transcribing"
        case let .downloading(progress):
            "Downloading model \(progress.percentTitle)"
        case let .preparing(progress):
            "Preparing model \(progress?.percentTitle ?? "0%")"
        case let .failed(message):
            message
        }
    }

    func helpText(hotkey: String) -> String {
        switch self {
        case .disabled:
            "Speech to Text disabled"
        case .ready:
            "Hold \(hotkey) for speech to text"
        default:
            accessibilityValue
        }
    }
}
