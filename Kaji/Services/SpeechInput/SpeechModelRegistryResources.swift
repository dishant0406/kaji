import Foundation

enum SpeechModelRegistryResources {
    static func loadBundled() throws -> SpeechModelRegistryDocument {
        let url = Bundle.module.url(forResource: "speech-models", withExtension: "json", subdirectory: "SpeechInput")
            ?? Bundle.module.url(forResource: "speech-models", withExtension: "json")
        guard let url else { return SpeechModelRegistryDocument(schemaVersion: 2, models: fallbackModels) }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SpeechModelRegistryDocument.self, from: data)
    }

    static let fallbackModels: [SpeechInputModel] = [
        SpeechInputModel(
            id: SpeechInputModel.defaultID,
            title: "Parakeet EOU 120M · 320 ms",
            detail: "Balanced low-latency English streaming dictation. Recommended default for Kaji.",
            engine: .fluidAudioParakeetEouStreaming,
            registryBaseURL: "https://huggingface.co",
            repo: "FluidInference/parakeet-realtime-eou-120m-coreml",
            revision: "main",
            subPath: "320ms",
            cachePath: "parakeet-eou-streaming/320ms",
            chunkSize: .ms320,
            estimatedDownloadSize: "213.85 MiB",
            recommended: true,
            requiredFiles: [
                "streaming_encoder.mlmodelc",
                "decoder.mlmodelc",
                "joint_decision.mlmodelc",
                "vocab.json",
            ],
            downloadBytes: 224_238_270,
            mode: .liveStreaming,
            languageSummary: "English",
            badges: ["Recommended", "Live", "English"],
            pros: ["Balanced latency and stability", "End-of-utterance aware"],
            cons: ["English only", "Lower quality than larger TDT models"]
        ),
    ]
}
