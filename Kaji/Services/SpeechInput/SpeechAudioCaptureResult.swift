import Foundation

struct SpeechAudioCaptureResult {
    let chunks: [SpeechAudioChunk]
    let droppedCount: Int
    let frameCount: Int

    static let empty = SpeechAudioCaptureResult(chunks: [], droppedCount: 0, frameCount: 0)
}
