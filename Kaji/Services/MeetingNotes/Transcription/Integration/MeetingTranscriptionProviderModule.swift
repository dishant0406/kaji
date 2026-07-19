import Foundation

enum MeetingTranscriptionProviderModuleError: Error, Equatable {
    case duplicateProvider(String)
    case providerUnavailable(String)
    case invalidRoute
    case credentialProfileRequired
    case credentialProfileMismatch
    case endpointProfileRequired
    case modelRequired
    case invalidConfiguration
}

struct MeetingTranscriptionProviderViewMetadata: Equatable {
    let privacySummary: String
    let costSummary: String
    let credentialLabel: String?
    let showsLocalModelDownloadAffordance: Bool
    let retentionPresentations: [MeetingTranscriptionRetentionPresentation]

    init(
        privacySummary: String,
        costSummary: String,
        credentialLabel: String?,
        showsLocalModelDownloadAffordance: Bool,
        retentionPresentations: [MeetingTranscriptionRetentionPresentation] = []
    ) {
        self.privacySummary = privacySummary
        self.costSummary = costSummary
        self.credentialLabel = credentialLabel
        self.showsLocalModelDownloadAffordance = showsLocalModelDownloadAffordance
        self.retentionPresentations = retentionPresentations
    }
}

struct MeetingTranscriptionRetentionPresentation: Equatable, Identifiable {
    let retention: MeetingTranscriptionDataRetentionClass
    let label: String
    let prerequisite: String
    let requiredAttestation: MeetingTranscriptionAccountAttestationKind?

    var id: MeetingTranscriptionDataRetentionClass { retention }
}

struct MeetingResolvedTranscriptionProvider {
    let provider: any MeetingTranscriptionProvider
    let route: MeetingTranscriptionRoute
    let keyterms: [String]
    let credentialProfileID: UUID?
    let localFallback: MeetingResolvedLocalTranscriptionFallback?

    init(
        provider: any MeetingTranscriptionProvider,
        route: MeetingTranscriptionRoute,
        keyterms: [String],
        credentialProfileID: UUID?,
        localFallback: MeetingResolvedLocalTranscriptionFallback? = nil
    ) {
        self.provider = provider
        self.route = route
        self.keyterms = keyterms
        self.credentialProfileID = credentialProfileID
        self.localFallback = localFallback
    }
}

struct MeetingResolvedLocalTranscriptionFallback {
    let provider: any MeetingTranscriptionProvider
    let route: MeetingTranscriptionRoute
}

@MainActor
protocol MeetingTranscriptionProviderModule: AnyObject {
    var descriptor: MeetingTranscriptionProviderDescriptor { get }
    var viewMetadata: MeetingTranscriptionProviderViewMetadata { get }
    func resolve(configuration: MeetingSessionConfiguration) throws -> MeetingResolvedTranscriptionProvider
}

struct MeetingTranscriptionModulePresentation: Identifiable {
    let descriptor: MeetingTranscriptionProviderDescriptor
    let viewMetadata: MeetingTranscriptionProviderViewMetadata

    var id: String { descriptor.id }
}

@MainActor
@Observable
final class MeetingTranscriptionProviderCatalog {
    static let shared = MeetingTranscriptionProviderCatalog.production()

    private let modulesByID: [String: any MeetingTranscriptionProviderModule]
    let credentialStore: any STTCredentialProfileStoring
    let endpointStore: MeetingTranscriptionEndpointStore
    let modelCatalogStore: MeetingTranscriptionModelCatalogStore

    init(
        modules: [any MeetingTranscriptionProviderModule],
        credentialStore: any STTCredentialProfileStoring,
        endpointStore: MeetingTranscriptionEndpointStore = .shared,
        modelCatalogStore: MeetingTranscriptionModelCatalogStore = .shared
    ) throws {
        let grouped = Dictionary(grouping: modules, by: { $0.descriptor.id })
        if let duplicate = grouped.first(where: { $0.value.count > 1 })?.key {
            throw MeetingTranscriptionProviderModuleError.duplicateProvider(duplicate)
        }
        modulesByID = Dictionary(uniqueKeysWithValues: modules.map { ($0.descriptor.id, $0) })
        self.credentialStore = credentialStore
        self.endpointStore = endpointStore
        self.modelCatalogStore = modelCatalogStore
    }

    var presentations: [MeetingTranscriptionModulePresentation] {
        modulesByID.values.map {
            MeetingTranscriptionModulePresentation(descriptor: $0.descriptor, viewMetadata: $0.viewMetadata)
        }.sorted { $0.descriptor.displayName < $1.descriptor.displayName }
    }

    func presentation(providerID: String) -> MeetingTranscriptionModulePresentation? {
        guard let module = modulesByID[providerID] else { return nil }
        return MeetingTranscriptionModulePresentation(descriptor: module.descriptor, viewMetadata: module.viewMetadata)
    }

    func resolve(configuration: MeetingSessionConfiguration) throws -> MeetingResolvedTranscriptionProvider {
        let route = configuration.transcriptionRoute
        guard let module = modulesByID[route.providerID] else {
            throw MeetingTranscriptionProviderModuleError.providerUnavailable(route.providerID)
        }
        try MeetingTranscriptionPrivacyPolicy.validate(configuration)
        let primary = try module.resolve(configuration: configuration)
        guard configuration.localFallbackEnabled,
              route.mode != .localChunked,
              let fallback = route.fallbacks.first(where: {
                  $0.mode == .localChunked && $0.providerID == FluidAudioMeetingTranscriptionProvider.providerID
              }),
              let localModule = modulesByID[fallback.providerID] as? FluidAudioTranscriptionProviderModule
        else {
            return primary
        }
        let localRoute = try MeetingTranscriptionRoute(
            providerID: fallback.providerID,
            modelID: fallback.modelID,
            languageCodes: route.languageCodes,
            regionID: fallback.regionID,
            mode: fallback.mode,
            diarizationEnabled: false,
            retention: .none
        )
        let localFallback = try localModule.resolveFallback(route: localRoute, keyterms: configuration.sttKeyterms)
        return MeetingResolvedTranscriptionProvider(
            provider: primary.provider,
            route: primary.route,
            keyterms: primary.keyterms,
            credentialProfileID: primary.credentialProfileID,
            localFallback: localFallback
        )
    }

    func endpointProfiles(providerID: String) -> [MeetingTranscriptionEndpointProfile] {
        endpointStore.profiles(providerID: providerID)
    }

    func credentialProfiles(providerID: String, endpoint: MeetingTranscriptionEndpointSnapshot?) throws -> [STTCredentialProfileMetadata] {
        try credentialStore.listMetadata().filter { metadata in
            guard metadata.providerID == providerID else { return false }
            guard let endpoint else { return metadata.endpointProfileID == nil }
            if metadata.endpointProfileID == endpoint.profileID,
               metadata.endpointOriginFingerprint == endpoint.originFingerprint
            {
                return true
            }
            return endpoint.source == .builtIn && metadata.endpointProfileID == nil && metadata.endpointOriginFingerprint == nil
        }
    }

    func saveCredential(
        id: UUID? = nil,
        providerID: String,
        endpoint: MeetingTranscriptionEndpointSnapshot,
        displayName: String,
        secret: Data,
        now: Date = Date()
    ) throws -> UUID {
        try endpoint.validate()
        guard endpoint.providerID == providerID else {
            throw MeetingTranscriptionProviderModuleError.credentialProfileMismatch
        }
        let existing = try credentialStore.listMetadata().first { $0.id == id }
        if let existing,
           existing.providerID != providerID ||
           existing.endpointProfileID != endpoint.profileID ||
           existing.endpointOriginFingerprint != endpoint.originFingerprint
        {
            throw MeetingTranscriptionProviderModuleError.credentialProfileMismatch
        }
        let metadata = try STTCredentialProfileMetadata(
            id: id ?? UUID(),
            providerID: providerID,
            displayName: displayName,
            endpointProfileID: endpoint.profileID,
            endpointOriginFingerprint: endpoint.originFingerprint,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try credentialStore.save(metadata: metadata, secret: secret)
        return metadata.id
    }

    func deleteCredential(profileID: UUID) throws {
        try credentialStore.delete(profileID: profileID)
    }

    func refreshModels(endpoint: MeetingTranscriptionEndpointSnapshot, credentialProfileID: UUID?) {
        modelCatalogStore.refresh(
            endpoint: endpoint,
            credentialProfileID: credentialProfileID,
            credentialStore: credentialStore
        )
    }

    func discoveredModels(
        endpointProfileID: UUID,
        credentialProfileID: UUID?
    ) -> [MeetingDiscoveredTranscriptionModel] {
        modelCatalogStore.catalog(
            endpointProfileID: endpointProfileID,
            credentialProfileID: credentialProfileID
        )?.models ?? []
    }

    private static func production() -> MeetingTranscriptionProviderCatalog {
        do {
            let metadataURL = KajiFileStorage.fileURL(filename: "meeting-stt-credential-profiles.json")
            let credentialStore = KeychainSTTCredentialProfileStore(
                metadata: FileSTTCredentialMetadataStore(fileURL: metadataURL)
            )
            let sessionPolicy = try STTURLSessionPolicy()
            let webSocketPolicy = try STTWebSocketPolicy()
            let webSocketFactory = URLSessionSTTWebSocketTransportFactory(
                sessionPolicy: sessionPolicy,
                webSocketPolicy: webSocketPolicy
            )
            let modules: [any MeetingTranscriptionProviderModule] = try [
                FluidAudioTranscriptionProviderModule(),
                OpenAITranscriptionProviderModule(
                    credentialStore: credentialStore,
                    httpTransportFactory: URLSessionOpenAIHTTPTransportFactory(policy: sessionPolicy),
                    webSocketFactory: webSocketFactory
                ),
                ElevenLabsTranscriptionProviderModule(
                    credentialStore: credentialStore,
                    sessionPolicy: sessionPolicy,
                    webSocketFactory: webSocketFactory
                ),
                DeepgramTranscriptionProviderModule(
                    credentialStore: credentialStore,
                    webSocketFactory: webSocketFactory
                ),
                AssemblyAITranscriptionProviderModule(
                    credentialStore: credentialStore,
                    webSocketFactory: webSocketFactory
                ),
            ]
            return try MeetingTranscriptionProviderCatalog(
                modules: modules,
                credentialStore: credentialStore,
                endpointStore: .shared,
                modelCatalogStore: .shared
            )
        } catch {
            preconditionFailure("Meeting transcription provider catalog could not be configured")
        }
    }
}

@MainActor
final class FluidAudioTranscriptionProviderModule: MeetingTranscriptionProviderModule {
    let viewMetadata = MeetingTranscriptionProviderViewMetadata(
        privacySummary: "Audio is processed on this Mac.",
        costSummary: "No provider usage charge.",
        credentialLabel: nil,
        showsLocalModelDownloadAffordance: true,
        retentionPresentations: [
            MeetingTranscriptionRetentionPresentation(
                retention: .none,
                label: "On-device processing",
                prerequisite: "Audio is processed on this Mac and is not retained by a cloud transcription provider.",
                requiredAttestation: nil
            ),
        ]
    )

    private let models: () -> [SpeechInputModel]
    private(set) var descriptor: MeetingTranscriptionProviderDescriptor

    init(models: @escaping () -> [SpeechInputModel] = { SpeechModelRegistryStore.shared.models }) throws {
        self.models = models
        descriptor = try FluidAudioMeetingTranscriptionProvider(models: Self.availableModels(models())).descriptor
    }

    func resolve(configuration: MeetingSessionConfiguration) throws -> MeetingResolvedTranscriptionProvider {
        let provider = try FluidAudioMeetingTranscriptionProvider(models: Self.availableModels(models()))
        try configuration.transcriptionRoute.validate(against: provider.descriptor)
        return MeetingResolvedTranscriptionProvider(
            provider: provider,
            route: configuration.transcriptionRoute,
            keyterms: configuration.sttKeyterms,
            credentialProfileID: nil
        )
    }

    func resolveFallback(
        route: MeetingTranscriptionRoute,
        keyterms: [String]
    ) throws -> MeetingResolvedLocalTranscriptionFallback {
        let provider = try FluidAudioMeetingTranscriptionProvider(models: Self.availableModels(models()))
        try route.validate(against: provider.descriptor)
        return MeetingResolvedLocalTranscriptionFallback(provider: provider, route: route)
    }

    private static func availableModels(_ models: [SpeechInputModel]) -> [SpeechInputModel] {
        models.isEmpty ? SpeechModelRegistryResources.fallbackModels : models
    }
}

private struct OpenAICredentialProfileResolver: OpenAICredentialSecretResolving {
    let profileID: UUID
    let store: any STTCredentialProfileStoring

    func resolveSecret() async throws -> Data {
        try store.loadSecret(profileID: profileID)
    }
}

@MainActor
final class OpenAITranscriptionProviderModule: MeetingTranscriptionProviderModule {
    let descriptor: MeetingTranscriptionProviderDescriptor
    let viewMetadata = MeetingTranscriptionProviderViewMetadata(
        privacySummary: "Raw audio is sent to the selected OpenAI-compatible endpoint.",
        costSummary: "Endpoint usage charges may apply.",
        credentialLabel: "API key",
        showsLocalModelDownloadAffordance: false,
        retentionPresentations: OpenAITranscriptionProviderModule.cloudRetention(
            standard: "OpenAI standard retention",
            standardDetail: "The endpoint operator's retention policy applies.",
            zero: "OpenAI Zero Data Retention",
            zeroDetail: "Requires an eligible OpenAI organization. Custom endpoint policies are unverified.",
            attestation: .openAIZeroDataRetention
        )
    )

    private let credentialStore: any STTCredentialProfileStoring
    private let httpTransportFactory: any OpenAIHTTPTransportFactory
    private let webSocketFactory: any STTWebSocketTransportFactory

    init(
        credentialStore: any STTCredentialProfileStoring,
        httpTransportFactory: any OpenAIHTTPTransportFactory,
        webSocketFactory: any STTWebSocketTransportFactory
    ) throws {
        self.credentialStore = credentialStore
        self.httpTransportFactory = httpTransportFactory
        self.webSocketFactory = webSocketFactory
        descriptor = try Self.emptyDescriptor(id: OpenAIMeetingTranscriptionProvider.providerID, name: "OpenAI")
    }

    func resolve(configuration: MeetingSessionConfiguration) throws -> MeetingResolvedTranscriptionProvider {
        let context = try dynamicContext(configuration, providerID: descriptor.id, store: credentialStore)
        let provider = try OpenAIMeetingTranscriptionProvider(
            secretResolver: OpenAICredentialProfileResolver(profileID: context.profileID, store: credentialStore),
            httpTransportFactory: httpTransportFactory,
            webSocketTransportFactory: EndpointProfileSTTWebSocketTransportFactory(
                underlying: webSocketFactory,
                endpoint: context.endpoint
            ),
            audioRateConverter: OpenAIPCM16AudioRateConverter(),
            configuration: OpenAIMeetingTranscriptionConfiguration(),
            endpoint: context.endpoint,
            model: context.model,
            mode: configuration.transcriptionRoute.mode,
            diarizationEnabled: configuration.transcriptionRoute.diarizationEnabled
        )
        return resolved(provider: provider, configuration: configuration, profileID: context.profileID)
    }
}

@MainActor
final class ElevenLabsTranscriptionProviderModule: MeetingTranscriptionProviderModule {
    let descriptor: MeetingTranscriptionProviderDescriptor
    let viewMetadata = MeetingTranscriptionProviderViewMetadata(
        privacySummary: "Raw audio is sent to the selected ElevenLabs-compatible endpoint.",
        costSummary: "Endpoint usage charges may apply.",
        credentialLabel: "API key",
        showsLocalModelDownloadAffordance: false,
        retentionPresentations: ElevenLabsTranscriptionProviderModule.cloudRetention(
            standard: "ElevenLabs standard retention",
            standardDetail: "The endpoint operator's retention policy applies.",
            zero: "Enterprise Zero Retention Mode",
            zeroDetail: "Requires an eligible workspace. Custom endpoint policies are unverified.",
            attestation: .elevenLabsZeroRetentionMode
        )
    )

    private let credentialStore: any STTCredentialProfileStoring
    private let sessionPolicy: STTURLSessionPolicy
    private let webSocketFactory: any STTWebSocketTransportFactory

    init(
        credentialStore: any STTCredentialProfileStoring,
        sessionPolicy: STTURLSessionPolicy,
        webSocketFactory: any STTWebSocketTransportFactory
    ) throws {
        self.credentialStore = credentialStore
        self.sessionPolicy = sessionPolicy
        self.webSocketFactory = webSocketFactory
        descriptor = try Self.emptyDescriptor(id: ElevenLabsScribeMeetingTranscriptionProvider.providerID, name: "ElevenLabs Scribe")
    }

    func resolve(configuration: MeetingSessionConfiguration) throws -> MeetingResolvedTranscriptionProvider {
        let context = try dynamicContext(configuration, providerID: descriptor.id, store: credentialStore)
        let provider = try ElevenLabsScribeMeetingTranscriptionProvider(
            credentialResolver: ElevenLabsScribeCredentialProfileResolver(
                profileID: context.profileID,
                store: credentialStore
            ),
            httpTransportFactory: URLSessionElevenLabsScribeHTTPTransportFactory(policy: sessionPolicy),
            webSocketTransportFactory: EndpointProfileSTTWebSocketTransportFactory(
                underlying: webSocketFactory,
                endpoint: context.endpoint
            ),
            batchOptions: ElevenLabsScribeBatchOptions(
                tagAudioEvents: configuration.sttProviderOptions.tagAudioEvents,
                noVerbatim: configuration.sttProviderOptions.noVerbatim,
                speakerCount: configuration.sttMaximumSpeakers
            ),
            realtimeOptions: ElevenLabsScribeRealtimeOptions(
                noVerbatim: configuration.sttProviderOptions.noVerbatim,
                includeLanguageDetection: configuration.sttProviderOptions.automaticLanguageDetection
            ),
            endpoint: context.endpoint,
            model: context.model,
            mode: configuration.transcriptionRoute.mode
        )
        return resolved(provider: provider, configuration: configuration, profileID: context.profileID)
    }
}

@MainActor
final class DeepgramTranscriptionProviderModule: MeetingTranscriptionProviderModule {
    let descriptor: MeetingTranscriptionProviderDescriptor
    let viewMetadata = MeetingTranscriptionProviderViewMetadata(
        privacySummary: "Raw audio is streamed to the selected Deepgram-compatible endpoint.",
        costSummary: "Endpoint usage charges may apply.",
        credentialLabel: "API key",
        showsLocalModelDownloadAffordance: false,
        retentionPresentations: DeepgramTranscriptionProviderModule.cloudRetention(
            standard: "Deepgram account default",
            standardDetail: "The endpoint operator's retention policy applies.",
            zero: "Request MIP opt-out",
            zeroDetail: "Kaji sends mip_opt_out=true to compatible hosted endpoints.",
            attestation: nil
        )
    )

    private let credentialStore: any STTCredentialProfileStoring
    private let webSocketFactory: any STTWebSocketTransportFactory

    init(
        credentialStore: any STTCredentialProfileStoring,
        webSocketFactory: any STTWebSocketTransportFactory
    ) throws {
        self.credentialStore = credentialStore
        self.webSocketFactory = webSocketFactory
        descriptor = try Self.emptyDescriptor(id: DeepgramMeetingTranscriptionProvider.providerID, name: "Deepgram")
    }

    func resolve(configuration: MeetingSessionConfiguration) throws -> MeetingResolvedTranscriptionProvider {
        let context = try dynamicContext(configuration, providerID: descriptor.id, store: credentialStore)
        let provider = try DeepgramMeetingTranscriptionProvider(
            configuration: DeepgramNova3Configuration(credentialProfileID: context.profileID),
            secretResolver: KeychainDeepgramAPIKeyResolver(credentialStore: credentialStore),
            transportFactory: EndpointProfileSTTWebSocketTransportFactory(
                underlying: webSocketFactory,
                endpoint: context.endpoint
            ),
            endpoint: context.endpoint,
            model: context.model
        )
        return resolved(provider: provider, configuration: configuration, profileID: context.profileID)
    }
}

@MainActor
final class AssemblyAITranscriptionProviderModule: MeetingTranscriptionProviderModule {
    let descriptor: MeetingTranscriptionProviderDescriptor
    let viewMetadata = MeetingTranscriptionProviderViewMetadata(
        privacySummary: "Raw audio is streamed to the selected AssemblyAI-compatible endpoint.",
        costSummary: "Endpoint usage charges may apply.",
        credentialLabel: "API key",
        showsLocalModelDownloadAffordance: false,
        retentionPresentations: AssemblyAITranscriptionProviderModule.cloudRetention(
            standard: "AssemblyAI account default",
            standardDetail: "The endpoint operator's retention policy applies.",
            zero: "Training opt-out / zero data retention",
            zeroDetail: "Requires account-level controls. Custom endpoint policies are unverified.",
            attestation: .assemblyAITrainingOptOut
        )
    )

    private let credentialStore: any STTCredentialProfileStoring
    private let webSocketFactory: any STTWebSocketTransportFactory

    init(
        credentialStore: any STTCredentialProfileStoring,
        webSocketFactory: any STTWebSocketTransportFactory
    ) throws {
        self.credentialStore = credentialStore
        self.webSocketFactory = webSocketFactory
        descriptor = try Self.emptyDescriptor(id: AssemblyAIMeetingTranscriptionProvider.providerID, name: "AssemblyAI")
    }

    func resolve(configuration: MeetingSessionConfiguration) throws -> MeetingResolvedTranscriptionProvider {
        let context = try dynamicContext(configuration, providerID: descriptor.id, store: credentialStore)
        let privacy = AssemblyAIAccountPrivacyConfiguration(
            trainingOptOutAttested: configuration.sttAccountAttestations.contains {
                $0.kind == .assemblyAITrainingOptOut && $0.isExact
            }
        )
        let resolver = AssemblyAISecretResolver {
            let data = try self.credentialStore.loadSecret(profileID: context.profileID)
            guard let value = String(data: data, encoding: .utf8), value.utf8.count == data.count else {
                throw AssemblyAIMeetingTranscriptionError.invalidCredential
            }
            return try AssemblyAIStreamingCredential(apiKey: value)
        }
        let provider = try AssemblyAIMeetingTranscriptionProvider(
            secretResolver: resolver,
            transportFactory: EndpointProfileSTTWebSocketTransportFactory(
                underlying: webSocketFactory,
                endpoint: context.endpoint
            ),
            configuration: AssemblyAIStreamingSessionConfiguration(
                maximumSpeakers: configuration.sttMaximumSpeakers,
                privacy: privacy
            ),
            endpoint: context.endpoint,
            model: context.model
        )
        return resolved(provider: provider, configuration: configuration, profileID: context.profileID)
    }
}

private struct MeetingDynamicProviderContext {
    let endpoint: MeetingTranscriptionEndpointSnapshot
    let model: MeetingDiscoveredTranscriptionModel
    let profileID: UUID
}

@MainActor
private func dynamicContext(
    _ configuration: MeetingSessionConfiguration,
    providerID: String,
    store: any STTCredentialProfileStoring
) throws -> MeetingDynamicProviderContext {
    guard let endpoint = configuration.transcriptionEndpoint else {
        throw MeetingTranscriptionProviderModuleError.endpointProfileRequired
    }
    try endpoint.validate()
    guard endpoint.providerID == providerID,
          endpoint.regionID == configuration.transcriptionRoute.regionID
    else {
        throw MeetingTranscriptionProviderModuleError.invalidRoute
    }
    let route = configuration.transcriptionRoute
    let model = try configuration.transcriptionModel ?? MeetingTranscriptionDynamicDescriptorFactory.manualModel(
        id: route.modelID,
        mode: route.mode
    )
    guard model.id == route.modelID, model.modes.contains(route.mode) else {
        throw MeetingTranscriptionProviderModuleError.modelRequired
    }
    let profileID = try requiredProfile(configuration, store: store, endpoint: endpoint)
    return MeetingDynamicProviderContext(endpoint: endpoint, model: model, profileID: profileID)
}

@MainActor
private func requiredProfile(
    _ configuration: MeetingSessionConfiguration,
    store: any STTCredentialProfileStoring,
    endpoint: MeetingTranscriptionEndpointSnapshot
) throws -> UUID {
    guard let profileID = configuration.sttCredentialProfileID else {
        throw MeetingTranscriptionProviderModuleError.credentialProfileRequired
    }
    let all = try store.listMetadata()
    guard let metadata = all.first(where: { $0.id == profileID }), metadata.providerID == endpoint.providerID else {
        throw MeetingTranscriptionProviderModuleError.credentialProfileMismatch
    }
    if metadata.endpointProfileID == endpoint.profileID,
       metadata.endpointOriginFingerprint == endpoint.originFingerprint
    {
        return profileID
    }
    guard metadata.endpointProfileID == nil,
          metadata.endpointOriginFingerprint == nil,
          endpoint.source == .builtIn
    else {
        throw MeetingTranscriptionProviderModuleError.credentialProfileMismatch
    }
    let secret = try store.loadSecret(profileID: profileID)
    let rebound = try STTCredentialProfileMetadata(
        id: metadata.id,
        providerID: metadata.providerID,
        displayName: metadata.displayName,
        endpointProfileID: endpoint.profileID,
        endpointOriginFingerprint: endpoint.originFingerprint,
        createdAt: metadata.createdAt,
        updatedAt: Date()
    )
    try store.save(metadata: rebound, secret: secret)
    return profileID
}

private func resolved(
    provider: any MeetingTranscriptionProvider,
    configuration: MeetingSessionConfiguration,
    profileID: UUID
) -> MeetingResolvedTranscriptionProvider {
    MeetingResolvedTranscriptionProvider(
        provider: provider,
        route: configuration.transcriptionRoute,
        keyterms: configuration.sttKeyterms,
        credentialProfileID: profileID
    )
}

private extension MeetingTranscriptionProviderModule {
    static func emptyDescriptor(id: String, name: String) throws -> MeetingTranscriptionProviderDescriptor {
        try MeetingTranscriptionProviderDescriptor(id: id, displayName: name, models: [], metadata: ["dynamicModels": "true"])
    }

    static func cloudRetention(
        standard: String,
        standardDetail: String,
        zero: String,
        zeroDetail: String,
        attestation: MeetingTranscriptionAccountAttestationKind?
    ) -> [MeetingTranscriptionRetentionPresentation] {
        [
            MeetingTranscriptionRetentionPresentation(
                retention: .providerDefault,
                label: standard,
                prerequisite: standardDetail,
                requiredAttestation: nil
            ),
            MeetingTranscriptionRetentionPresentation(
                retention: .none,
                label: zero,
                prerequisite: zeroDetail,
                requiredAttestation: attestation
            ),
            MeetingTranscriptionRetentionPresentation(
                retention: .configurable,
                label: "Custom endpoint policy",
                prerequisite: "The custom endpoint operator controls retention. Kaji cannot verify that policy.",
                requiredAttestation: nil
            ),
        ]
    }
}

enum MeetingTranscriptionPrivacyPolicy {
    static func validate(_ configuration: MeetingSessionConfiguration) throws {
        let route = configuration.transcriptionRoute
        if configuration.transcriptionEndpoint?.source == .custom {
            guard route.retention == .configurable else {
                throw MeetingTranscriptionProviderModuleError.invalidConfiguration
            }
            return
        }
        let required: MeetingTranscriptionAccountAttestationKind? = switch (route.providerID, route.mode, route.retention) {
        case (OpenAIMeetingTranscriptionProvider.providerID, .cloudRealtime, .none):
            .openAIZeroDataRetention
        case (AssemblyAIMeetingTranscriptionProvider.providerID, _, .none):
            .assemblyAITrainingOptOut
        case (ElevenLabsScribeMeetingTranscriptionProvider.providerID, _, .none):
            .elevenLabsZeroRetentionMode
        default:
            nil
        }
        guard let required else { return }
        guard configuration.sttAccountAttestations.contains(where: {
            $0.kind == required && $0.isExact && $0.providerID == route.providerID
        })
        else {
            throw MeetingTranscriptionProviderModuleError.invalidConfiguration
        }
    }
}
