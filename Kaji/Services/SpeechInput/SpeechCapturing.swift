import AVFoundation
import Foundation

@MainActor
protocol SpeechCapturing: AnyObject {
    func start(session: SpeechCaptureSession) throws
    func snapshotChunk() -> SpeechAudioChunk?
    func finish(session: SpeechCaptureSession?, reason: SpeechCaptureStopReason) -> SpeechAudioChunk?
}
