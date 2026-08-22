import Foundation

actor SpeechTranscriber: SpeechTranscribing {
    typealias ProgressHandler = @Sendable (SpeechDownloadProgress) -> Void

    nonisolated let downloader: HuggingFaceModelDownloader
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
        let result = try await transcript(chunks: chunks, model: model)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw SpeechInputError.emptyTranscript }
        return result
    }

    func download(model: SpeechInputModel, progress: ProgressHandler? = nil) async throws {
        try await downloader.download(model: model, progress: progress)
    }

    func unload() async {
        await eouRuntime.unload()
        await tdtRuntime.unload()
    }

    func beginSession(model: SpeechInputModel) async throws {
        guard model.cacheState.isReady else { throw SpeechInputError.modelUnavailable }
        try await eouRuntime.beginSession(model: model)
    }

    func append(chunks: [SpeechAudioChunk], model: SpeechInputModel) async throws -> String? {
        guard model.cacheState.isReady else { throw SpeechInputError.modelUnavailable }
        guard !chunks.isEmpty else { return nil }
        try await eouRuntime.append(chunks: chunks)
        let partial = try await eouRuntime.partialTranscript()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return partial.isEmpty ? nil : partial
    }

    func finishSession(model: SpeechInputModel) async throws -> String {
        guard model.cacheState.isReady else { throw SpeechInputError.modelUnavailable }
        let transcript = try await eouRuntime.finish()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { throw SpeechInputError.emptyTranscript }
        return transcript
    }

    func cancelSession() async {
        await eouRuntime.unload()
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
