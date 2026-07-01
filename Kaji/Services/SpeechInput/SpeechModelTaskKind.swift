import Foundation

enum SpeechModelTaskKind {
    case download
    case prepare

    var initialProgress: SpeechDownloadProgress {
        switch self {
        case .download: .starting
        case .prepare: .preparing
        }
    }

    func status(_ progress: SpeechDownloadProgress) -> SpeechInputStatus {
        switch self {
        case .download: .downloading(progress)
        case .prepare: .preparing(progress)
        }
    }
}
