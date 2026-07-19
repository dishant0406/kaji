import Combine
import Foundation
import Testing

@testable import Kaji

@MainActor
@Suite("Meeting transcription settings controller")
struct MeetingTranscriptionSettingsControllerTests {
    @Test("local configuration exposes only the local model path")
    func localProgressiveDisclosure() throws {
        let fixture = try Fixture()
        let controller = fixture.controller

        controller.start()

        #expect(!controller.showsEndpoint)
        #expect(!controller.showsCredential)
        #expect(!controller.showsMode)
        guard case let .local(models) = controller.modelControlState else {
            Issue.record("Expected local model state")
            return
        }
        #expect(!models.isEmpty)
        #expect(controller.endpointEditorState == .hidden)
        #expect(controller.credentialEditorState == .hidden)
    }

    @Test("cloud configuration asks for endpoint credentials before models")
    func cloudProgressiveDisclosure() throws {
        let fixture = try Fixture()
        let controller = fixture.controller

        controller.start()
        controller.selectProvider(OpenAIMeetingTranscriptionProvider.providerID)

        #expect(controller.showsEndpoint)
        #expect(controller.showsCredential)
        #expect(controller.showsMode)
        #expect(controller.endpointEditorState == .hidden)
        #expect(controller.credentialEditorState == .hidden)
        #expect(controller.modelControlState == .credentialRequired)
        #expect(fixture.discoverer.requestCount == 0)
    }

    @Test("endpoint editor is transactional and hidden until requested")
    func endpointEditorTransitions() throws {
        let fixture = try Fixture()
        let controller = fixture.controller
        controller.start()
        controller.selectProvider(OpenAIMeetingTranscriptionProvider.providerID)
        let initialEndpoint = controller.settingsStore.settings.sttEndpointSnapshot

        controller.beginCreateEndpoint()
        #expect(controller.endpointEditorState == .creating)
        controller.endpointName = "Unsaved"
        controller.restBaseURL = "https://speech.example.com/v1"
        controller.webSocketBaseURL = "wss://speech.example.com/v1"
        controller.cancelEndpointEditor()

        #expect(controller.endpointEditorState == .hidden)
        #expect(controller.settingsStore.settings.sttEndpointSnapshot == initialEndpoint)
    }
    @Test("editor transitions publish observable changes")
    func editorTransitionsPublish() throws {
        let fixture = try Fixture()
        let controller = fixture.controller
        controller.start()
        controller.selectProvider(OpenAIMeetingTranscriptionProvider.providerID)
        var publications = 0
        let token = controller.objectWillChange.sink { publications += 1 }

        controller.beginCreateEndpoint()
        #expect(controller.endpointEditorState == .creating)
        #expect(publications > 0)

        controller.cancelEndpointEditor()
        #expect(controller.endpointEditorState == .hidden)
        withExtendedLifetime(token) {}
    }

    @Test("saving an API key automatically loads models once")
    func credentialTriggersDiscovery() async throws {
        let fixture = try Fixture()
        let controller = fixture.controller
        controller.start()
        controller.selectProvider(OpenAIMeetingTranscriptionProvider.providerID)
        controller.refreshModels()
        #expect(fixture.discoverer.requestCount == 0)

        controller.beginCreateCredential()
        controller.credentialName = "Work"
        controller.credentialSecret = "secret"
        controller.saveCredential()
        try await fixture.waitForDiscovery(count: 1)

        #expect(fixture.discoverer.requestCount == 1)
        #expect(controller.settingsStore.settings.sttCredentialProfileID != nil)
        guard case let .loaded(models, isStale, isRefreshing) = controller.modelControlState else {
            Issue.record("Expected loaded models")
            return
        }
        #expect(models.map(\.id) == ["account-audio"])
        #expect(!isStale)
        #expect(!isRefreshing)
    }

    @Test("selecting an existing API key loads uncached models")
    func existingCredentialTriggersDiscovery() async throws {
        let fixture = try Fixture()
        let controller = fixture.controller
        controller.start()
        controller.selectProvider(OpenAIMeetingTranscriptionProvider.providerID)
        let endpoint = try #require(controller.settingsStore.settings.sttEndpointSnapshot)
        let profileID = try fixture.catalog.saveCredential(
            providerID: endpoint.providerID,
            endpoint: endpoint,
            displayName: "Existing",
            secret: Data("secret".utf8)
        )
        controller.start()

        controller.selectCredential(profileID)
        try await fixture.waitForDiscovery(count: 1)

        #expect(fixture.discoverer.requestCount == 1)
        #expect(controller.settingsStore.settings.sttCredentialProfileID == profileID)
    }

    @Test("fixed-mode manual providers hide mode and discovery controls")
    func manualProviderState() throws {
        let fixture = try Fixture()
        let controller = fixture.controller
        controller.start()

        controller.selectProvider(AssemblyAIMeetingTranscriptionProvider.providerID)

        #expect(!controller.showsMode)
        #expect(controller.modelControlState == .manual)
        #expect(controller.settingsStore.settings.sttMode == .cloudRealtime)
    }

    @Test("changing endpoints clears endpoint-bound credentials and models")
    func endpointChangeClearsBoundSelection() throws {
        let fixture = try Fixture()
        let controller = fixture.controller
        controller.start()
        controller.selectProvider(OpenAIMeetingTranscriptionProvider.providerID)
        let first = try #require(controller.settingsStore.settings.sttEndpointSnapshot)
        let profileID = try fixture.catalog.saveCredential(
            providerID: first.providerID,
            endpoint: first,
            displayName: "Bound",
            secret: Data("secret".utf8)
        )
        controller.selectCredential(profileID)
        controller.manualModelID = "manual-model"
        controller.useManualModel()
        let second = try #require(fixture.endpointStore.profiles(providerID: first.providerID).last)

        controller.selectEndpoint(second.id)

        #expect(controller.settingsStore.settings.sttCredentialProfileID == nil)
        #expect(controller.settingsStore.settings.sttModelID.isEmpty)
        #expect(controller.settingsStore.settings.sttModelMetadata == nil)
    }
}

@MainActor
private struct Fixture {
    let discoverer = CountingModelDiscoverer()
    let endpointStore: MeetingTranscriptionEndpointStore
    let catalog: MeetingTranscriptionProviderCatalog
    let controller: MeetingTranscriptionSettingsController

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingTranscriptionSettingsControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        endpointStore = MeetingTranscriptionEndpointStore(
            fileURL: root.appendingPathComponent("endpoints.json"),
            bundledLoader: { try Self.endpointDocument() }
        )
        let credentials = InMemorySTTCredentialProfileStore()
        let modelCatalog = MeetingTranscriptionModelCatalogStore(
            discoverer: discoverer,
            fileURL: root.appendingPathComponent("models.json")
        )
        catalog = try MeetingTranscriptionProviderCatalog(
            modules: [
                SettingsControllerTestModule(
                    id: FluidAudioMeetingTranscriptionProvider.providerID,
                    name: "FluidAudio",
                    credentialLabel: nil,
                    local: true
                ),
                SettingsControllerTestModule(
                    id: OpenAIMeetingTranscriptionProvider.providerID,
                    name: "OpenAI",
                    credentialLabel: "API key",
                    local: false
                ),
                SettingsControllerTestModule(
                    id: AssemblyAIMeetingTranscriptionProvider.providerID,
                    name: "AssemblyAI",
                    credentialLabel: "API key",
                    local: false
                ),
            ],
            credentialStore: credentials,
            endpointStore: endpointStore,
            modelCatalogStore: modelCatalog
        )
        let settingsStore = MeetingNotesSettingsStore(
            fileStore: .init(fileURL: root.appendingPathComponent("settings.json"), options: .prettySorted)
        )
        controller = MeetingTranscriptionSettingsController(settingsStore: settingsStore, catalog: catalog)
    }

    func waitForDiscovery(count: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while discoverer.requestCount < count, clock.now < deadline {
            try await clock.sleep(for: .milliseconds(10))
        }
        #expect(discoverer.requestCount == count)
    }

    private static func endpointDocument() throws -> MeetingTranscriptionEndpointRegistryDocument {
        try MeetingTranscriptionEndpointRegistryDocument(profiles: [
            endpoint(
                id: "00000000-0000-4000-8000-000000000001",
                providerID: FluidAudioMeetingTranscriptionProvider.providerID,
                name: "This Mac",
                variant: .fluidAudioLocal,
                regionID: "local",
                rest: nil,
                socket: nil,
                discovery: .localRegistry
            ),
            endpoint(
                id: "00000000-0000-4000-8000-000000000101",
                providerID: OpenAIMeetingTranscriptionProvider.providerID,
                name: "OpenAI Global",
                variant: .openAICompatible,
                regionID: "global",
                rest: "https://api.openai.com/v1",
                socket: "wss://api.openai.com/v1",
                discovery: .openAIModels
            ),
            endpoint(
                id: "00000000-0000-4000-8000-000000000102",
                providerID: OpenAIMeetingTranscriptionProvider.providerID,
                name: "OpenAI Europe",
                variant: .openAICompatible,
                regionID: "eu",
                rest: "https://eu.api.openai.com/v1",
                socket: "wss://eu.api.openai.com/v1",
                discovery: .openAIModels
            ),
            endpoint(
                id: "00000000-0000-4000-8000-000000000401",
                providerID: AssemblyAIMeetingTranscriptionProvider.providerID,
                name: "AssemblyAI",
                variant: .assemblyAIStreamingV3,
                regionID: "global",
                rest: nil,
                socket: "wss://streaming.assemblyai.com",
                discovery: .manual
            ),
        ])
    }

    private static func endpoint(
        id: String,
        providerID: String,
        name: String,
        variant: MeetingTranscriptionProtocolVariant,
        regionID: String,
        rest: String?,
        socket: String?,
        discovery: MeetingTranscriptionModelDiscoveryKind
    ) throws -> MeetingTranscriptionEndpointProfile {
        let discoveryPath: String? = discovery == .openAIModels ? "/models" : nil
        return try MeetingTranscriptionEndpointProfile(
            id: #require(UUID(uuidString: id)),
            providerID: providerID,
            displayName: name,
            variant: variant,
            regionID: regionID,
            restBaseURL: rest,
            webSocketBaseURL: socket,
            discovery: MeetingTranscriptionModelDiscoveryConfiguration(
                kind: discovery,
                path: discoveryPath
            ),
            source: .builtIn
        )
    }
}

private final class SettingsControllerTestModule: MeetingTranscriptionProviderModule {
    let descriptor: MeetingTranscriptionProviderDescriptor
    let viewMetadata: MeetingTranscriptionProviderViewMetadata

    @MainActor
    init(id: String, name: String, credentialLabel: String?, local: Bool) throws {
        let models: [MeetingTranscriptionModelDescriptor]
        if local {
            models = try FluidAudioMeetingTranscriptionProvider(
                models: [MeetingAudioTestFixtures.model]
            ).descriptor.models
        } else {
            models = []
        }
        descriptor = try MeetingTranscriptionProviderDescriptor(
            id: id,
            displayName: name,
            models: models
        )
        viewMetadata = MeetingTranscriptionProviderViewMetadata(
            privacySummary: name,
            costSummary: "",
            credentialLabel: credentialLabel,
            showsLocalModelDownloadAffordance: local,
            retentionPresentations: local ? [
                MeetingTranscriptionRetentionPresentation(
                    retention: .none,
                    label: "On device",
                    prerequisite: "Local",
                    requiredAttestation: nil
                ),
            ] : [
                MeetingTranscriptionRetentionPresentation(
                    retention: .providerDefault,
                    label: "Provider default",
                    prerequisite: "Provider",
                    requiredAttestation: nil
                ),
                MeetingTranscriptionRetentionPresentation(
                    retention: .configurable,
                    label: "Endpoint policy",
                    prerequisite: "Endpoint",
                    requiredAttestation: nil
                ),
            ]
        )
    }

    @MainActor
    func resolve(configuration _: MeetingSessionConfiguration) throws -> MeetingResolvedTranscriptionProvider {
        throw MeetingTranscriptionProviderModuleError.invalidConfiguration
    }
}

private final class CountingModelDiscoverer: MeetingTranscriptionModelDiscovering, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var requestCount: Int {
        lock.withLock { count }
    }

    func discover(
        endpoint _: MeetingTranscriptionEndpointSnapshot,
        credentialProfileID _: UUID?,
        credentialStore _: any STTCredentialProfileStoring
    ) async throws -> [MeetingDiscoveredTranscriptionModel] {
        lock.withLock { count += 1 }
        return [try MeetingDiscoveredTranscriptionModel(
            id: "account-audio",
            displayName: "Account Audio",
            modes: [.cloudBatch, .cloudRealtime],
            capabilityConfidence: .providerReported
        )]
    }
}
