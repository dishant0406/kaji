import Foundation
import Testing

@testable import Kaji

@Suite("Speech input controller")
@MainActor
struct SpeechInputControllerTests {
    @Test("enable is blocked when selected model is not ready")
    func enableBlockedWithoutModel() {
        let store = SpeechInputSettingsStore(fileURL: tempURL())
        let controller = SpeechInputController(settingsStore: store, modelRegistry: registryStore()) { _ in .missing }
        controller.setEnabled(true)
        #expect(!store.settings.isEnabled)
        #expect(controller.status == .error("Download the selected speech model before enabling speech to text."))
    }

    @Test("selecting a missing model disables speech")
    func selectingMissingModelDisablesSpeech() {
        let store = SpeechInputSettingsStore(fileURL: tempURL())
        let controller = SpeechInputController(settingsStore: store, modelRegistry: registryStore()) { model in
            model.id == SpeechInputModel.defaultID ? .ready : .missing
        }
        controller.setEnabled(true)
        controller.selectModel(id: "parakeet-eou-160ms")
        #expect(!store.settings.isEnabled)
        #expect(store.settings.selectedModelID == "parakeet-eou-160ms")
    }

    private func tempURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechInputControllerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    private func registryStore() -> SpeechModelRegistryStore {
        SpeechModelRegistryStore(fileURL: tempURL()) {
            SpeechModelRegistryDocument(schemaVersion: 1, models: SpeechModelRegistryResources.fallbackModels + [
                SpeechInputModel(
                    id: "parakeet-eou-160ms",
                    title: "Parakeet EOU 120M · 160 ms",
                    detail: "Lowest latency",
                    engine: .fluidAudioParakeetEouStreaming,
                    registryBaseURL: "https://huggingface.co",
                    repo: "FluidInference/parakeet-realtime-eou-120m-coreml",
                    revision: "main",
                    subPath: "160ms",
                    cachePath: "parakeet-eou-streaming/160ms",
                    chunkSize: .ms160,
                    estimatedDownloadSize: "~1.25 GB",
                    recommended: false,
                    requiredFiles: ["streaming_encoder.mlmodelc", "decoder.mlmodelc", "joint_decision.mlmodelc", "vocab.json"]
                ),
            ])
        }
    }
}
