@preconcurrency import CoreML
import FluidAudio
import Foundation

actor SpeechEouTranscriptionRuntime {
    private var manager: StreamingEouAsrManager?
    private var loadedModelID: String?
    private var hasLoadedModels = false
    private var hasSessionAudio = false
    private var deliveredPartial = ""

    func prepare(model: SpeechInputModel) async throws {
        try await beginSession(model: model)
    }

    func transcribe(chunks: [SpeechAudioChunk], model: SpeechInputModel) async throws -> String {
        try await beginSession(model: model)
        try await append(chunks: chunks)
        return try await finish()
    }

    func beginSession(model: SpeechInputModel) async throws {
        let manager = try await self.manager(for: model)
        if !hasLoadedModels {
            try await manager.loadModels(from: model.cacheURL)
            hasLoadedModels = true
        }
        await manager.reset()
        hasSessionAudio = false
        deliveredPartial = ""
    }

    func append(chunks: [SpeechAudioChunk]) async throws {
        guard !chunks.isEmpty else { return }
        let manager = try currentManager()
        for chunk in chunks {
            guard chunk.sampleRate == SpeechAudioSampleRate.targetHz else {
                throw SpeechInputError.emptyAudio
            }
            guard let buffer = chunk.makeBuffer() else { throw SpeechInputError.emptyAudio }
            try await manager.appendAudio(buffer)
            try await manager.processBufferedAudio()
            hasSessionAudio = true
        }
    }

    func partialTranscript() async -> String {
        guard let manager else { return "" }
        let full = await manager.getPartialTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
        guard full.hasPrefix(deliveredPartial) else { return full }
        let delta = full.dropFirst(deliveredPartial.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !delta.isEmpty else { return "" }
        deliveredPartial = full
        return delta
    }

    func finish() async throws -> String {
        defer { deliveredPartial = "" }
        guard hasSessionAudio else { throw SpeechInputError.emptyAudio }
        hasSessionAudio = false
        let full = try await currentManager().finish().trimmingCharacters(in: .whitespacesAndNewlines)
        guard full.hasPrefix(deliveredPartial) else { return full }
        return full.dropFirst(deliveredPartial.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unload() async {
        let current = manager
        manager = nil
        loadedModelID = nil
        hasLoadedModels = false
        hasSessionAudio = false
        deliveredPartial = ""
        await current?.cleanup()
    }

    private func currentManager() throws -> StreamingEouAsrManager {
        guard let manager else { throw SpeechInputError.modelUnavailable }
        return manager
    }

    private func manager(for model: SpeechInputModel) async throws -> StreamingEouAsrManager {
        guard model.engine == .fluidAudioParakeetEouStreaming else { throw SpeechInputError.modelUnavailable }
        if let manager, loadedModelID == model.id {
            return manager
        }
        await manager?.cleanup()
        guard let chunkSize = model.chunkSize else { throw SpeechInputError.modelUnavailable }
        let next = StreamingEouAsrManager(configuration: MLModelConfiguration(), chunkSize: Self.chunkSize(chunkSize))
        manager = next
        loadedModelID = model.id
        hasLoadedModels = false
        return next
    }

    private static func chunkSize(_ chunkSize: SpeechModelChunkSize) -> StreamingChunkSize {
        switch chunkSize {
        case .ms160: .ms160
        case .ms320: .ms320
        case .ms1280: .ms1280
        }
    }
}
