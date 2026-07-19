import Foundation
import Testing

@testable import Kaji

@MainActor
@Suite("Meeting transcription endpoint and model discovery")
struct EndpointModelDiscoveryTests {
    @Test("custom endpoint snapshots normalize and freeze exact destinations")
    func endpointSnapshot() throws {
        let profile = try customProfile(id: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")))
        let snapshot = profile.snapshot

        #expect(snapshot.restBaseURL == "https://speech.example.com/v1")
        #expect(snapshot.webSocketBaseURL == "wss://speech.example.com/v1")
        #expect(try snapshot.restURL(path: "/models").absoluteString == "https://speech.example.com/v1/models")
        #expect(try snapshot.webSocketURL(path: "/realtime").absoluteString == "wss://speech.example.com/v1/realtime")
        try snapshot.validate()
    }

    @Test("custom endpoints reject plaintext private metadata and credential URLs", arguments: [
        "http://speech.example.com/v1",
        "https://127.0.0.1/v1",
        "https://169.254.169.254/v1",
        "https://user:secret@speech.example.com/v1",
        "https://speech.example.com/v1?token=secret",
    ])
    func unsafeEndpoints(value: String) throws {
        #expect(throws: Error.self) {
            let profile = try MeetingTranscriptionEndpointProfile(
                providerID: OpenAIMeetingTranscriptionProvider.providerID,
                displayName: "Unsafe",
                variant: .openAICompatible,
                regionID: "unsafe",
                restBaseURL: value,
                webSocketBaseURL: "wss://speech.example.com/v1",
                discovery: MeetingTranscriptionModelDiscoveryConfiguration(kind: .manual),
                source: .custom
            )
            let store = MeetingTranscriptionEndpointStore(
                fileURL: temporaryURL("unsafe-endpoints.json"),
                bundledLoader: { try builtInDocument() }
            )
            try store.saveCustom(profile)
        }
    }

    @Test("custom endpoint persistence merges immutable presets and preserves permissions")
    func endpointPersistence() throws {
        let fileURL = temporaryURL("custom-endpoints.json")
        let store = MeetingTranscriptionEndpointStore(
            fileURL: fileURL,
            bundledLoader: { try builtInDocument() }
        )
        let custom = try customProfile(id: #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")))

        try store.saveCustom(custom)
        let reloaded = MeetingTranscriptionEndpointStore(
            fileURL: fileURL,
            bundledLoader: { try builtInDocument() }
        )

        #expect(reloaded.profiles.count == 2)
        #expect(reloaded.profile(id: custom.id) == custom)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("credentials cannot cross endpoint origins")
    func endpointCredentialBinding() throws {
        let credentialStore = InMemorySTTCredentialProfileStore()
        let endpointStore = MeetingTranscriptionEndpointStore(
            fileURL: temporaryURL("credential-endpoints.json"),
            bundledLoader: { try builtInDocument() }
        )
        let catalog = try MeetingTranscriptionProviderCatalog(
            modules: [CatalogEndpointTestModule()],
            credentialStore: credentialStore,
            endpointStore: endpointStore,
            modelCatalogStore: MeetingTranscriptionModelCatalogStore(
                discoverer: nil,
                fileURL: temporaryURL("credential-models.json")
            )
        )
        let first = endpointStore.profiles[0].snapshot
        let other = try customProfile(id: #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))).snapshot
        let profileID = try catalog.saveCredential(
            providerID: first.providerID,
            endpoint: first,
            displayName: "Bound",
            secret: Data("secret".utf8)
        )

        #expect(try catalog.credentialProfiles(providerID: first.providerID, endpoint: first).map(\.id) == [profileID])
        #expect(try catalog.credentialProfiles(providerID: first.providerID, endpoint: other).isEmpty)
        #expect(throws: MeetingTranscriptionProviderModuleError.credentialProfileMismatch) {
            _ = try catalog.saveCredential(
                id: profileID,
                providerID: other.providerID,
                endpoint: other,
                displayName: "Rebound",
                secret: Data("secret".utf8)
            )
        }
    }

    @Test("official model responses are decoded without compiled model allowlists")
    func providerModelDecoding() throws {
        let openAI = try RemoteMeetingTranscriptionModelDiscovery.decodeOpenAI(Data("""
        {"object":"list","data":[{"id":"account-audio-deployment","owned_by":"customer"}]}
        """.utf8))
        let deepgram = try RemoteMeetingTranscriptionModelDiscovery.decodeDeepgram(Data("""
        {"stt":[{"name":"private-meeting-model","canonical_name":"Private Meeting","languages":["en","es"],"batch":true,"streaming":true}]}
        """.utf8))
        let elevenLabs = try RemoteMeetingTranscriptionModelDiscovery.decodeElevenLabs(Data("""
        [{"model_id":"workspace-scribe","name":"Workspace Scribe","languages":[{"language_id":"en","name":"English"}]}]
        """.utf8))

        #expect(openAI.map(\.id) == ["account-audio-deployment"])
        #expect(openAI[0].modes == [.cloudBatch, .cloudRealtime])
        #expect(deepgram.map(\.id) == ["private-meeting-model"])
        #expect(deepgram[0].modes == [.cloudRealtime])
        #expect(deepgram[0].metadata["batchAvailable"] == "true")
        #expect(elevenLabs.map(\.id) == ["workspace-scribe"])
        #expect(elevenLabs[0].metadata["sttCompatibility"] == "unverified")
    }

    @Test("session consent freezes endpoint and discovered model")
    func frozenConsent() throws {
        let endpoint = try customProfile(id: #require(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"))).snapshot
        let model = try MeetingTranscriptionDynamicDescriptorFactory.manualModel(
            id: "deployment-a",
            mode: .cloudRealtime
        )
        var settings = MeetingNotesIntegrationSettings.defaults
        settings.sttProviderID = endpoint.providerID
        settings.sttEndpointProfileID = endpoint.profileID
        settings.sttEndpointSnapshot = endpoint
        settings.sttModelID = model.id
        settings.sttModelMetadata = model
        settings.sttMode = .cloudRealtime
        settings.sttRegionID = endpoint.regionID
        settings.sttRetention = .configurable

        let configuration = settings.sessionConfiguration(consentedAtMilliseconds: 1000)

        #expect(configuration.transcriptionEndpoint == endpoint)
        #expect(configuration.transcriptionModel == model)
        #expect(configuration.rawAudioRecipient == "speech.example.com")
        #expect(configuration.rawAudioRetention == .configurable)
        #expect(configuration.disclosureClaims.contains { $0.contains("speech.example.com") })
    }

    private func customProfile(id: UUID) throws -> MeetingTranscriptionEndpointProfile {
        try MeetingTranscriptionEndpointProfile(
            id: id,
            providerID: OpenAIMeetingTranscriptionProvider.providerID,
            displayName: "Corporate OpenAI",
            variant: .openAICompatible,
            regionID: "custom-\(id.uuidString.lowercased().prefix(8))",
            restBaseURL: "https://speech.example.com/v1/",
            webSocketBaseURL: "wss://speech.example.com/v1/",
            discovery: MeetingTranscriptionModelDiscoveryConfiguration(kind: .openAIModels, path: "/models"),
            source: .custom
        )
    }

    private func builtInDocument() throws -> MeetingTranscriptionEndpointRegistryDocument {
        try MeetingTranscriptionEndpointRegistryDocument(profiles: [
            MeetingTranscriptionEndpointProfile(
                id: #require(UUID(uuidString: "00000000-0000-4000-8000-000000000101")),
                providerID: OpenAIMeetingTranscriptionProvider.providerID,
                displayName: "OpenAI",
                variant: .openAICompatible,
                regionID: "global",
                restBaseURL: "https://api.openai.com/v1",
                webSocketBaseURL: "wss://api.openai.com/v1",
                discovery: MeetingTranscriptionModelDiscoveryConfiguration(kind: .openAIModels, path: "/models"),
                source: .builtIn
            ),
        ])
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
    }
}

@MainActor
private final class CatalogEndpointTestModule: MeetingTranscriptionProviderModule {
    let descriptor: MeetingTranscriptionProviderDescriptor
    let viewMetadata = MeetingTranscriptionProviderViewMetadata(
        privacySummary: "Test",
        costSummary: "Test",
        credentialLabel: "Key",
        showsLocalModelDownloadAffordance: false
    )

    init() throws {
        descriptor = try MeetingTranscriptionProviderDescriptor(
            id: OpenAIMeetingTranscriptionProvider.providerID,
            displayName: "OpenAI",
            models: []
        )
    }

    func resolve(configuration _: MeetingSessionConfiguration) throws -> MeetingResolvedTranscriptionProvider {
        throw MeetingTranscriptionProviderModuleError.invalidConfiguration
    }
}
