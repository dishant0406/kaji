@preconcurrency import CoreML
import FluidAudio
import Foundation

actor SpeechEouTranscriptionRuntime {
    private var manager: StreamingEouAsrManager?
    private var loadedModelID: String?

    func prepare(model: SpeechInputModel) async throws {
        let manager = try await manager(for: model)
        try await manager.loadModels(from: model.cacheURL)
    }

    func transcribe(chunks: [SpeechAudioChunk], model: SpeechInputModel) async throws -> String {
        let manager = try await manager(for: model)
        try await manager.loadModels(from: model.cacheURL)
        await manager.reset()
        for chunk in chunks {
            guard let buffer = chunk.makeBuffer() else { throw SpeechInputError.emptyAudio }
            try await manager.appendAudio(buffer)
            try await manager.processBufferedAudio()
        }
        return try await manager.finish()
    }

    func unload() async {
        let current = manager
        manager = nil
        loadedModelID = nil
        await current?.cleanup()
    }

    private func manager(for model: SpeechInputModel) async throws -> StreamingEouAsrManager {
        guard model.engine == .fluidAudioParakeetEouStreaming else { throw SpeechInputError.modelUnavailable }
        if let manager, loadedModelID == model.id { return manager }
        await manager?.cleanup()
        guard let chunkSize = model.chunkSize else { throw SpeechInputError.modelUnavailable }
        let next = StreamingEouAsrManager(configuration: MLModelConfiguration(), chunkSize: Self.chunkSize(chunkSize))
        manager = next
        loadedModelID = model.id
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
