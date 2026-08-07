import Foundation

actor SpeechTranscriber: SpeechTranscribing {
    typealias ProgressHandler = @Sendable (SpeechDownloadProgress) -> Void

    private let downloader: HuggingFaceModelDownloader
    private let eouRuntime = SpeechEouTranscriptionRuntime()
    private let tdtRuntime = SpeechParakeetTdtTranscriptionRuntime()

    init(downloader: HuggingFaceModelDownloader = HuggingFaceModelDownloader()) {
        self.downloader = downloader
    }

    func prepare(model: SpeechInputModel, progress: ProgressHandler? = nil) async throws {
        if !model.cacheState.isReady {
            try await download(model: model, progress: progress)
        }
        switch model.engine {
        case .fluidAudioParakeetEouStreaming:
            try await eouRuntime.prepare(model: model)
            await tdtRuntime.unload()
        case .fluidAudioParakeetTdt:
            try await tdtRuntime.prepare(model: model)
            await eouRuntime.unload()
        }
    }

    func transcribe(chunks: [SpeechAudioChunk], model: SpeechInputModel) async throws -> String {
        guard model.cacheState.isReady else { throw SpeechInputError.modelUnavailable }
        guard !chunks.isEmpty else { throw SpeechInputError.emptyAudio }
        let transcript = try await transcript(chunks: chunks, model: model)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { throw SpeechInputError.emptyTranscript }
        return transcript
    }

    func download(model: SpeechInputModel, progress: ProgressHandler? = nil) async throws {
        try await downloader.download(model: model, progress: progress)
    }

    func unload() async {
        await eouRuntime.unload()
        await tdtRuntime.unload()
    }

    private func transcript(chunks: [SpeechAudioChunk], model: SpeechInputModel) async throws -> String {
        switch model.engine {
        case .fluidAudioParakeetEouStreaming:
            await tdtRuntime.unload()
            return try await eouRuntime.transcribe(chunks: chunks, model: model)
        case .fluidAudioParakeetTdt:
            await eouRuntime.unload()
            return try await tdtRuntime.transcribe(chunks: chunks, model: model)
        }
    }
}
