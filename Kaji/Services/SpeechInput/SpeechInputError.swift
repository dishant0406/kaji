import Foundation

enum SpeechInputError: LocalizedError {
    case microphonePermissionDenied
    case audioInputUnavailable
    case emptyAudio
    case emptyTranscript
    case noInsertionTarget
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone access is needed for speech to text. Enable it in System Settings."
        case .audioInputUnavailable:
            "No usable microphone input was found. Check your audio input device and try again."
        case .emptyAudio:
            "No speech audio was captured."
        case .emptyTranscript:
            "No words were detected."
        case .noInsertionTarget:
            "No active cursor was found for inserting speech text."
        case .modelUnavailable:
            "Download the selected speech model before enabling speech to text."
        }
    }
}
