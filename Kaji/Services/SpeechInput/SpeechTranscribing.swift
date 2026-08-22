import Foundation

protocol SpeechTranscribing: Sendable {
    func prepare(model: SpeechInputModel, progress: SpeechTranscriber.ProgressHandler?) async throws
    func transcribe(chunks: [SpeechAudioChunk], model: SpeechInputModel) async throws -> String
    func download(model: SpeechInputModel, progress: SpeechTranscriber.ProgressHandler?) async throws
    func unload() async
    func beginSession(model: SpeechInputModel) async throws
    func append(chunks: [SpeechAudioChunk], model: SpeechInputModel) async throws -> String?
    func finishSession(model: SpeechInputModel) async throws -> String
    func cancelSession() async
}
