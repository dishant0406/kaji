import Foundation

struct SpeechInputPendingChunk {
    let chunk: SpeechAudioChunk
    let settings: SpeechInputSettings
    let model: SpeechInputModel
}
