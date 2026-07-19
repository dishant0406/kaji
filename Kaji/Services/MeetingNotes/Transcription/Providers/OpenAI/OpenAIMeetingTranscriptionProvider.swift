import Foundation

final class OpenAIMeetingTranscriptionProvider: MeetingTranscriptionProvider, @unchecked Sendable {
    static let providerID = "openai"
    static let maximumUploadBytes = 25 * 1024 * 1024

    let descriptor: MeetingTranscriptionProviderDescriptor

    private let secretResolver: any OpenAICredentialSecretResolving
    private let httpTransportFactory: any OpenAIHTTPTransportFactory
    private let webSocketTransportFactory: any STTWebSocketTransportFactory
    private let audioRateConverter: any OpenAIAudioRateConverting
    private let configuration: OpenAIMeetingTranscriptionConfiguration
    private let endpoint: MeetingTranscriptionEndpointSnapshot
    private let selectedModels: [String: MeetingDiscoveredTranscriptionModel]
    private let endpointValidator: any MeetingTranscriptionEndpointResolving
    private let nowMilliseconds: @Sendable () -> Int64

    init(
        secretResolver: any OpenAICredentialSecretResolving,
        httpTransportFactory: any OpenAIHTTPTransportFactory,
        webSocketTransportFactory: any STTWebSocketTransportFactory,
        audioRateConverter: any OpenAIAudioRateConverting = OpenAIAlready24kHzAudioRateConverter(),
        configuration: OpenAIMeetingTranscriptionConfiguration,
        endpoint: MeetingTranscriptionEndpointSnapshot,
        model: MeetingDiscoveredTranscriptionModel,
        models: [MeetingDiscoveredTranscriptionModel]? = nil,
        mode: MeetingTranscriptionMode,
        diarizationEnabled: Bool,
        endpointValidator: any MeetingTranscriptionEndpointResolving = MeetingTranscriptionEndpointResolutionValidator(),
        nowMilliseconds: @escaping @Sendable () -> Int64 = {
            max(0, Int64(Date().timeIntervalSince1970 * 1000))
        }
    ) throws {
        guard endpoint.providerID == Self.providerID,
              endpoint.variant == .openAICompatible,
              (models ?? [model]).allSatisfy({ !$0.modes.isEmpty })
        else {
            throw OpenAIMeetingTranscriptionError.invalidConfiguration
        }
        descriptor = try MeetingTranscriptionDynamicDescriptorFactory.providerDescriptor(
            providerID: Self.providerID,
            displayName: "OpenAI",
            models: models ?? [model],
            endpoint: endpoint,
            selectedMode: nil,
            diarizationEnabled: true
        )
        self.secretResolver = secretResolver
        self.httpTransportFactory = httpTransportFactory
        self.webSocketTransportFactory = webSocketTransportFactory
        self.audioRateConverter = audioRateConverter
        self.configuration = configuration
        self.endpoint = endpoint
        selectedModels = Dictionary(uniqueKeysWithValues: (models ?? [model]).map { ($0.id, $0) })
        self.endpointValidator = endpointValidator
        self.nowMilliseconds = nowMilliseconds
    }

    func route(
        languageCode: String? = nil,
        retention: MeetingTranscriptionDataRetentionClass? = nil
    ) throws -> MeetingTranscriptionRoute {
        guard let model = selectedModels.values.min(by: { $0.id < $1.id }),
              let mode = model.modes.min(by: { $0.rawValue < $1.rawValue })
        else {
            throw OpenAIMeetingTranscriptionError.invalidConfiguration
        }
        let route = try MeetingTranscriptionRoute(
            providerID: Self.providerID,
            modelID: model.id,
            languageCodes: languageCode.map { [$0] } ?? [],
            regionID: endpoint.regionID,
            mode: mode,
            diarizationEnabled: false,
            retention: retention ?? (endpoint.source == .custom ? .configurable : .providerDefault)
        )
        try validate(route: route)
        return route
    }

    func readiness(for route: MeetingTranscriptionRoute) async -> MeetingTranscriptionReadiness {
        guard (try? validate(route: route)) != nil else { return .unavailable }
        do {
            try await endpointValidator.validate(endpoint)
            let secret = try await secretResolver.resolveSecret()
            _ = try OpenAICredentialValidator.bearerToken(from: secret)
            return .ready
        } catch {
            return (try? MeetingTranscriptionReadiness(
                state: .requiresConfiguration,
                reason: "The OpenAI-compatible endpoint or credential is unavailable."
            )) ?? .unavailable
        }
    }

    func makeSession(
        route: MeetingTranscriptionRoute,
        context: any MeetingTrackTranscriptionContext
    ) async throws -> any MeetingTrackTranscriptionSession {
        try validate(route: route)
        try await endpointValidator.validate(endpoint)
        let token: String
        do {
            let secret = try await secretResolver.resolveSecret()
            token = try OpenAICredentialValidator.bearerToken(from: secret)
        } catch {
            throw OpenAIMeetingTranscriptionError.invalidCredential
        }
        let snapshot = try MeetingTrackTranscriptionContextSnapshot(
            sessionID: context.sessionID,
            trackID: context.trackID,
            source: context.source,
            canonicalSampleRateHertz: context.canonicalSampleRateHertz,
            channelCount: context.channelCount,
            startedAtMilliseconds: context.startedAtMilliseconds,
            keyterms: context.keyterms
        )
        if route.mode == .cloudBatch {
            return try OpenAIBatchTranscriptionSession(
                route: route,
                endpoint: OpenAIEndpoint.batch(endpoint),
                context: snapshot,
                bearerToken: token,
                transport: httpTransportFactory.makeTransport(),
                configuration: configuration,
                nowMilliseconds: nowMilliseconds
            )
        }
        return try OpenAIRealtimeTranscriptionSession(
            route: route,
            endpoint: OpenAIEndpoint.realtime(endpoint),
            context: snapshot,
            bearerToken: token,
            transport: webSocketTransportFactory.makeTransport(),
            audioRateConverter: audioRateConverter,
            configuration: configuration,
            nowMilliseconds: nowMilliseconds
        )
    }

    private func validate(route: MeetingTranscriptionRoute) throws {
        do {
            try route.validate(against: descriptor)
        } catch {
            throw OpenAIMeetingTranscriptionError.invalidRoute
        }
        guard route.providerID == Self.providerID,
              let model = selectedModels[route.modelID],
              model.modes.contains(route.mode),
              route.regionID == endpoint.regionID,
              route.languageCodes.count <= 1,
              !route.diarizationEnabled || route.mode == .cloudBatch
        else {
            throw OpenAIMeetingTranscriptionError.invalidRoute
        }
    }
}

enum OpenAIEndpoint {
    static func batch(_ endpoint: MeetingTranscriptionEndpointSnapshot) throws -> URL {
        try endpoint.restURL(path: "/audio/transcriptions")
    }

    static func realtime(_ endpoint: MeetingTranscriptionEndpointSnapshot) throws -> URL {
        let base = try endpoint.webSocketURL(path: "/realtime")
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw OpenAIMeetingTranscriptionError.invalidConfiguration
        }
        components.queryItems = [URLQueryItem(name: "intent", value: "transcription")]
        guard let url = components.url else { throw OpenAIMeetingTranscriptionError.invalidConfiguration }
        return url
    }

    static func validateFinal(_ url: URL, expected: URL) throws {
        guard origin(url) == origin(expected),
              url.path == expected.path,
              url.query == expected.query,
              url.fragment == nil,
              url.user == nil,
              url.password == nil
        else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
    }

    static func authorize(_ request: inout URLRequest, token: String, expected: URL) throws {
        guard let url = request.url,
              origin(url) == origin(expected),
              url.path == expected.path,
              url.query == expected.query
        else {
            throw OpenAIMeetingTranscriptionError.invalidRoute
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private static func origin(_ url: URL) -> String {
        "\(url.scheme?.lowercased() ?? "")://\(url.host?.lowercased() ?? ""):\(url.port ?? 443)"
    }
}
