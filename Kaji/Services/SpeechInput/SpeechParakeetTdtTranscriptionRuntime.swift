@preconcurrency import CoreML
import FluidAudio
import Foundation

actor SpeechParakeetTdtTranscriptionRuntime {
    private var manager: AsrManager?
    private var loadedModelID: String?

    func prepare(model: SpeechInputModel) async throws {
        _ = try await manager(for: model)
    }

    func transcribe(chunks: [SpeechAudioChunk], model: SpeechInputModel) async throws -> String {
        let manager = try await manager(for: model)
        let samples = chunks.flatMap(\.samples)
        guard !samples.isEmpty else { throw SpeechInputError.emptyAudio }
        var state = try TdtDecoderState(decoderLayers: runtime(model).asrVersion.decoderLayers)
        let result = try await manager.transcribe(samples, decoderState: &state, language: runtime(model).language)
        return result.text
    }

    func unload() async {
        let current = manager
        manager = nil
        loadedModelID = nil
        await current?.cleanup()
    }

    private func manager(for model: SpeechInputModel) async throws -> AsrManager {
        guard model.engine == .fluidAudioParakeetTdt else { throw SpeechInputError.modelUnavailable }
        if let manager, loadedModelID == model.id { return manager }
        await manager?.cleanup()
        let runtime = try runtime(model)
        let models = try await AsrModels.load(
            from: model.cacheURL,
            configuration: MLModelConfiguration(),
            version: runtime.asrVersion.fluidAudioVersion,
            encoderPrecision: runtime.encoderPrecision.fluidAudioPrecision
        )
        let next = AsrManager(config: runtime.asrConfig, models: models)
        manager = next
        loadedModelID = model.id
        return next
    }

    private func runtime(_ model: SpeechInputModel) throws -> SpeechParakeetTdtRuntime {
        guard let config = model.runtime, let version = config.asrVersion else {
            throw SpeechInputError.modelUnavailable
        }
        return SpeechParakeetTdtRuntime(
            asrVersion: version,
            encoderPrecision: config.encoderPrecision ?? .int8,
            language: config.language?.fluidAudioLanguage,
            melChunkContext: config.melChunkContext
        )
    }
}

private struct SpeechParakeetTdtRuntime {
    let asrVersion: SpeechModelAsrVersion
    let encoderPrecision: SpeechModelEncoderPrecision
    let language: Language?
    let melChunkContext: Bool?

    var asrConfig: ASRConfig {
        ASRConfig(
            encoderHiddenSize: asrVersion.encoderHiddenSize,
            melChunkContext: melChunkContext ?? asrVersion.defaultMelChunkContext
        )
    }
}

private extension SpeechModelAsrVersion {
    var defaultMelChunkContext: Bool {
        self != .v3
    }
}
