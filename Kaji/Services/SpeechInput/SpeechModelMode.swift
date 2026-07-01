import Foundation

enum SpeechModelMode: String, Codable, Equatable, Hashable {
    case liveStreaming
    case releaseTranscription

    var title: String {
        switch self {
        case .liveStreaming: "Live"
        case .releaseTranscription: "After release"
        }
    }

    var detail: String {
        switch self {
        case .liveStreaming: "Streams partial audio while you hold the shortcut."
        case .releaseTranscription: "Records while held, then transcribes after release."
        }
    }
}
