import Foundation
import Testing

@testable import Kaji

@MainActor
@Suite("Meeting transcription provider modules")
struct MeetingTranscriptionProviderModuleTests {
    @Test("catalog accepts a new module without coordinator provider changes")
    func catalogAddition() throws {
        let store = InMemorySTTCredentialProfileStore()
        let module = try CatalogTestModule()
        let catalog = try MeetingTranscriptionProviderCatalog(modules: [module], credentialStore: store)
        var settings = MeetingNotesIntegrationSettings.defaults
        let route = try MeetingTranscriptionCoreFixtures.route()
        settings.sttProviderID = route.providerID
        settings.sttModelID = route.modelID
        settings.sttMode = route.mode
        settings.sttRegionID = route.regionID
        settings.sttRetention = route.retention
        settings.sttLanguageCodes = route.languageCodes
        settings.sttDiarizationEnabled = route.diarizationEnabled

        let resolved = try catalog.resolve(configuration: settings.sessionConfiguration(consentedAtMilliseconds: 1_000))

        #expect(catalog.presentations.map(\.id) == [route.providerID])
        #expect(resolved.route == route)
    }

    @Test("local fallback resolves only from frozen consent and an explicit local route")
    func explicitLocalFallback() throws {
        let store = InMemorySTTCredentialProfileStore()
        let cloud = try CatalogTestModule()
        let local = try FluidAudioTranscriptionProviderModule(models: { [MeetingAudioTestFixtures.model] })
        let catalog = try MeetingTranscriptionProviderCatalog(modules: [cloud, local], credentialStore: store)
        var settings = MeetingNotesIntegrationSettings.defaults
        settings.sttProviderID = cloud.descriptor.id
        settings.sttModelID = try #require(cloud.descriptor.models.first?.id)
        settings.sttMode = .cloudRealtime
        settings.sttRegionID = "local"
        settings.sttRetention = .none
        settings.localFallbackEnabled = true

        let consented = settings.sessionConfiguration(consentedAtMilliseconds: 1_000)
        let resolved = try catalog.resolve(configuration: consented)
        #expect(consented.transcriptionRoute.fallbacks.count == 1)
        #expect(resolved.localFallback?.route.mode == .localChunked)
        #expect(resolved.localFallback?.route.providerID == FluidAudioMeetingTranscriptionProvider.providerID)

        settings.localFallbackEnabled = false
        let disabled = try catalog.resolve(configuration: settings.sessionConfiguration(consentedAtMilliseconds: 1_000))
        #expect(disabled.localFallback == nil)
    }

    @Test("OpenAI module captures an in-memory Keychain profile and rejects deletion")
    func credentialProfileIntegration() async throws {
        let store = InMemorySTTCredentialProfileStore()
        let profile = try STTCredentialProfileMetadata(
            providerID: OpenAIMeetingTranscriptionProvider.providerID,
            displayName: "Test"
        )
        try store.save(metadata: profile, secret: Data("sk-test-value".utf8))
        let http = OpenAITestHTTPTransport()
        let webSocket = OpenAITestWebSocketTransport()
        let module = try OpenAITranscriptionProviderModule(
            credentialStore: store,
            httpTransportFactory: OpenAITestHTTPTransportFactory(transport: http),
            webSocketFactory: OpenAITestWebSocketTransportFactory(transport: webSocket)
        )
        let catalog = try MeetingTranscriptionProviderCatalog(modules: [module], credentialStore: store)
        var settings = MeetingNotesIntegrationSettings.defaults
        settings.sttProviderID = OpenAIMeetingTranscriptionProvider.providerID
        settings.sttModelID = OpenAITranscriptionModel.miniTranscribe.rawValue
        settings.sttMode = .cloudBatch
        settings.sttRegionID = OpenAITranscriptionRegion.global.rawValue
        settings.sttRetention = .none
        settings.sttCredentialProfileID = profile.id
        let endpoint = try OpenAIMeetingTranscriptionTestFixtures.endpoint()
        settings.sttEndpointProfileID = endpoint.profileID
        settings.sttEndpointSnapshot = endpoint
        settings.sttModelMetadata = try OpenAIMeetingTranscriptionTestFixtures.model(.miniTranscribe)
        let configuration = settings.sessionConfiguration(consentedAtMilliseconds: 1_000)

        let active = try catalog.resolve(configuration: configuration)
        #expect(await active.provider.readiness(for: active.route).state == .ready)
        let session = try await active.provider.makeSession(
            route: active.route,
            context: MeetingTrackTranscriptionContextSnapshot(
                sessionID: UUID(),
                trackID: UUID(),
                source: .microphone,
                canonicalSampleRateHertz: 16_000,
                channelCount: 1,
                startedAtMilliseconds: 1_000
            )
        )

        try catalog.deleteCredential(profileID: profile.id)

        #expect(throws: MeetingTranscriptionProviderModuleError.self) {
            _ = try catalog.resolve(configuration: configuration)
        }
        await session.cancel()
        #expect(await http.cancelled())
    }

    @Test("account-controlled no-retention routes require exact attestations")
    func retentionAttestations() throws {
        let cases: [(String, MeetingTranscriptionMode, MeetingTranscriptionAccountAttestationKind)] = [
            (OpenAIMeetingTranscriptionProvider.providerID, .cloudRealtime, .openAIZeroDataRetention),
            (AssemblyAIMeetingTranscriptionProvider.providerID, .cloudRealtime, .assemblyAITrainingOptOut),
            (ElevenLabsScribeMeetingTranscriptionProvider.providerID, .cloudRealtime, .elevenLabsZeroRetentionMode),
        ]
        for (providerID, mode, kind) in cases {
            var settings = MeetingNotesIntegrationSettings.defaults
            settings.sttProviderID = providerID
            settings.sttModelID = "model"
            settings.sttMode = mode
            settings.sttRegionID = "global"
            settings.sttRetention = .none
            let unattested = settings.sessionConfiguration(consentedAtMilliseconds: 1_000)
            #expect(throws: MeetingTranscriptionProviderModuleError.invalidConfiguration) {
                try MeetingTranscriptionPrivacyPolicy.validate(unattested)
            }

            settings.sttAccountAttestations = [try MeetingTranscriptionAccountAttestation(
                kind: kind,
                acceptedAtMilliseconds: 900
            )]
            try MeetingTranscriptionPrivacyPolicy.validate(
                settings.sessionConfiguration(consentedAtMilliseconds: 1_000)
            )
        }
    }

    @Test("provider retention presentation uses human policy labels")
    func retentionPresentation() throws {
        let store = InMemorySTTCredentialProfileStore()
        let sessionPolicy = try STTURLSessionPolicy()
        let socket = OpenAITestWebSocketTransportFactory(transport: OpenAITestWebSocketTransport())
        let modules: [any MeetingTranscriptionProviderModule] = [
            try OpenAITranscriptionProviderModule(
                credentialStore: store,
                httpTransportFactory: OpenAITestHTTPTransportFactory(transport: OpenAITestHTTPTransport()),
                webSocketFactory: socket
            ),
            try ElevenLabsTranscriptionProviderModule(
                credentialStore: store,
                sessionPolicy: sessionPolicy,
                webSocketFactory: socket
            ),
            try DeepgramTranscriptionProviderModule(credentialStore: store, webSocketFactory: socket),
            try AssemblyAITranscriptionProviderModule(credentialStore: store, webSocketFactory: socket),
        ]
        let catalog = try MeetingTranscriptionProviderCatalog(modules: modules, credentialStore: store)

        for presentation in catalog.presentations {
            #expect(!presentation.viewMetadata.retentionPresentations.isEmpty)
            #expect(presentation.viewMetadata.retentionPresentations.allSatisfy {
                !$0.label.isEmpty && !$0.prerequisite.isEmpty && $0.label != $0.retention.rawValue
            })
        }
    }
}

@MainActor
private final class CatalogTestModule: MeetingTranscriptionProviderModule {
    let provider: CatalogTestProvider
    let descriptor: MeetingTranscriptionProviderDescriptor
    let viewMetadata = MeetingTranscriptionProviderViewMetadata(
        privacySummary: "Test",
        costSummary: "Test",
        credentialLabel: nil,
        showsLocalModelDownloadAffordance: false
    )

    init() throws {
        let provider = try CatalogTestProvider()
        self.provider = provider
        descriptor = provider.descriptor
    }

    func resolve(configuration: MeetingSessionConfiguration) throws -> MeetingResolvedTranscriptionProvider {
        try configuration.transcriptionRoute.validate(against: descriptor)
        return MeetingResolvedTranscriptionProvider(
            provider: provider,
            route: configuration.transcriptionRoute,
            keyterms: configuration.sttKeyterms,
            credentialProfileID: nil
        )
    }
}

private final class CatalogTestProvider: MeetingTranscriptionProvider, @unchecked Sendable {
    let descriptor: MeetingTranscriptionProviderDescriptor

    init() throws {
        descriptor = try MeetingTranscriptionCoreFixtures.descriptor()
    }

    func readiness(for _: MeetingTranscriptionRoute) async -> MeetingTranscriptionReadiness {
        .ready
    }

    func makeSession(
        route _: MeetingTranscriptionRoute,
        context _: any MeetingTrackTranscriptionContext
    ) async throws -> any MeetingTrackTranscriptionSession {
        throw MeetingTranscriptionProviderModuleError.invalidConfiguration
    }
}
