import Foundation

struct SpeechCaptureSession: Equatable {
    let id: UUID
    let startedAt: Date

    static func start(now: Date = Date()) -> SpeechCaptureSession {
        SpeechCaptureSession(id: UUID(), startedAt: now)
    }

    var logID: String {
        String(id.uuidString.prefix(8))
    }
}
