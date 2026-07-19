import Foundation
import Testing

@testable import Kaji

@Suite("Speech model registry")
@MainActor
struct SpeechModelRegistryTests {
    @Test("bundled catalog loads expanded speech models")
    func bundledCatalogLoadsExpandedModels() throws {
        let bundled = try SpeechModelRegistryResources.loadBundled()
        #expect(bundled.schemaVersion == 2)
        #expect(bundled.models.count >= 8)
        #expect(bundled.models.contains { $0.id == "parakeet-tdt-v3-int8" })
    }

    @Test("registry writes bundled json when user file is missing")
    func writesBundledRegistry() throws {
        let url = tempURL()
        let store = SpeechModelRegistryStore(fileURL: url, bundledLoader: bundledDocument)
        #expect(store.models.map(\.id) == [SpeechInputModel.defaultID])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("registry loads user edited json")
    func loadsUserRegistry() throws {
        let url = tempURL()
        let model = customModel(id: "custom-parakeet")
        try save(url, SpeechModelRegistryDocument(schemaVersion: 2, models: [model]))
        let store = SpeechModelRegistryStore(fileURL: url, bundledLoader: bundledDocument)
        #expect(store.models == [model])
        #expect(store.model(for: "missing").id == "custom-parakeet")
    }

    @Test("old bundled entries migrate to expanded catalog")
    func migratesBundledEntries() throws {
        let url = tempURL()
        try save(url, SpeechModelRegistryDocument(schemaVersion: 1, models: [oldDefaultModel(), customModel(id: "custom")]))
        let bundled = SpeechModelRegistryDocument(schemaVersion: 2, models: [expandedDefaultModel(), parakeetV3Model()])
        let store = SpeechModelRegistryStore(fileURL: url) { bundled }
        #expect(store.models.map(\.id) == [SpeechInputModel.defaultID, "parakeet-tdt-v3-int8", "custom"])
        #expect(store.models[0].downloadBytes == 224_238_270)
    }

    @Test("same schema bundled stub expands to bundled catalog")
    func expandsBundledStub() throws {
        let url = tempURL()
        try save(url, SpeechModelRegistryDocument(schemaVersion: 2, models: [oldDefaultModel(), customModel(id: "custom")]))
        let bundled = SpeechModelRegistryDocument(schemaVersion: 2, models: [expandedDefaultModel(), parakeetV3Model()])
        let store = SpeechModelRegistryStore(fileURL: url) { bundled }
        #expect(store.models.map(\.id) == [SpeechInputModel.defaultID, "parakeet-tdt-v3-int8", "custom"])
        #expect(store.models[0].repo == "FluidInference/parakeet-realtime-eou-120m-coreml")
    }

    @Test("invalid registry falls back and keeps error")
    func invalidRegistryFallback() throws {
        let url = tempURL()
        try "{}".data(using: .utf8)?.write(to: url)
        let store = SpeechModelRegistryStore(fileURL: url, bundledLoader: bundledDocument)
        #expect(store.models.map(\.id) == [SpeechInputModel.defaultID])
        #expect(store.lastError != nil)
    }

    @Test("remote file mapper strips model subpath")
    func remoteFileMapper() {
        let required = ["encoder.mlmodelc", "vocab.json"]
        #expect(SpeechModelRemoteFileMapper.localPath(remotePath: "320ms/encoder.mlmodelc/coremldata.bin", subPath: "320ms") == "encoder.mlmodelc/coremldata.bin")
        #expect(SpeechModelRemoteFileMapper.shouldInclude(remotePath: "320ms/encoder.mlmodelc/coremldata.bin", subPath: "320ms", requiredFiles: required))
        #expect(!SpeechModelRemoteFileMapper.shouldInclude(remotePath: "320ms/other.bin", subPath: "320ms", requiredFiles: required))
        #expect(!SpeechModelRemoteFileMapper.shouldInclude(remotePath: "320ms/../vocab.json", subPath: "320ms", requiredFiles: required))
        #expect(!SpeechModelRemoteFileMapper.shouldInclude(remotePath: "/320ms/vocab.json", subPath: "320ms", requiredFiles: required))
        #expect(!SpeechModelRemoteFileMapper.shouldInclude(remotePath: "320ms//vocab.json", subPath: "320ms", requiredFiles: required))
    }

    @Test("registry rejects untrusted origins and unsafe repository paths")
    func rejectsUntrustedRegistryInput() throws {
        for baseURL in [
            "http://huggingface.co",
            "https://huggingface.co.evil.example",
            "https://user@huggingface.co",
            "https://huggingface.co:443",
            "https://127.0.0.1",
        ] {
            let document = SpeechModelRegistryDocument(
                schemaVersion: 2,
                models: [customModel(id: "unsafe", registryBaseURL: baseURL)]
            )
            #expect(throws: SpeechModelRegistryError.self) {
                try SpeechModelRegistryValidator.validate(document)
            }
        }

        let unsafeRepo = SpeechModelRegistryDocument(
            schemaVersion: 2,
            models: [customModel(id: "unsafe", repo: "Example/../private")]
        )
        #expect(throws: SpeechModelRegistryError.self) {
            try SpeechModelRegistryValidator.validate(unsafeRepo)
        }
    }

    @Test("credentials are restricted to the trusted registry origin")
    func restrictsCredentialOrigin() throws {
        #expect(SpeechModelRegistrySecurity.shouldAttachToken(to: try #require(URL(string: "https://huggingface.co/api/models"))))
        #expect(!SpeechModelRegistrySecurity.shouldAttachToken(to: try #require(URL(string: "https://huggingface.co.evil.example/api"))))
        #expect(!SpeechModelRegistrySecurity.shouldAttachToken(to: try #require(URL(string: "http://huggingface.co/api"))))
        #expect(!SpeechModelRegistrySecurity.shouldAttachToken(to: try #require(URL(string: "https://127.0.0.1/api"))))
    }

    private func bundledDocument() -> SpeechModelRegistryDocument {
        SpeechModelRegistryDocument(schemaVersion: 2, models: SpeechModelRegistryResources.fallbackModels)
    }

    private func save(_ url: URL, _ document: SpeechModelRegistryDocument) throws {
        try CodableFileStore(fileURL: url, options: .prettySorted).save(document)
    }

    private func customModel(
        id: String,
        registryBaseURL: String = "https://huggingface.co",
        repo: String = "Example/custom-coreml"
    ) -> SpeechInputModel {
        SpeechInputModel(
            id: id,
            title: "Custom Parakeet",
            detail: "Custom compatible model",
            engine: .fluidAudioParakeetEouStreaming,
            registryBaseURL: registryBaseURL,
            repo: repo,
            revision: "main",
            subPath: "320ms",
            cachePath: "custom/320ms",
            chunkSize: .ms320,
            estimatedDownloadSize: "213.85 MiB",
            recommended: false,
            requiredFiles: ["streaming_encoder.mlmodelc", "decoder.mlmodelc", "joint_decision.mlmodelc", "vocab.json"]
        )
    }

    private func oldDefaultModel() -> SpeechInputModel {
        customModel(id: SpeechInputModel.defaultID)
    }

    private func expandedDefaultModel() -> SpeechInputModel {
        SpeechModelRegistryResources.fallbackModels[0]
    }

    private func parakeetV3Model() -> SpeechInputModel {
        SpeechInputModel(
            id: "parakeet-tdt-v3-int8",
            title: "Parakeet TDT v3",
            detail: "Multilingual",
            engine: .fluidAudioParakeetTdt,
            registryBaseURL: "https://huggingface.co",
            repo: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
            revision: "main",
            subPath: nil,
            cachePath: "parakeet-tdt-0.6b-v3",
            chunkSize: nil,
            estimatedDownloadSize: "460.73 MiB",
            recommended: false,
            requiredFiles: ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecisionv3.mlmodelc", "parakeet_vocab.json"],
            downloadBytes: 483_105_645,
            runtime: SpeechModelRuntimeConfig(asrVersion: .v3, encoderPrecision: .int8, language: nil, melChunkContext: false)
        )
    }

    private func tempURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechModelRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("speech-models.json")
    }
}
