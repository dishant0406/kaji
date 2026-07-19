import Foundation

enum DeepgramMeetingTranscriptionError: Error, Equatable {
    case invalidConfiguration
    case invalidRoute
    case credentialUnavailable
    case invalidCredential
    case invalidPacket
    case invalidState
    case responseTooLarge
    case protocolViolation
    case providerRejected(MeetingTranscriptionFailureClassification)
}

protocol DeepgramAPIKeyResolving: Sendable {
    func resolveAPIKey(profileID: UUID) throws -> Data
}

struct KeychainDeepgramAPIKeyResolver: DeepgramAPIKeyResolving {
    let credentialStore: any STTCredentialProfileStoring

    func resolveAPIKey(profileID: UUID) throws -> Data {
        try credentialStore.loadSecret(profileID: profileID)
    }
}

struct DeepgramWebSocketResponseMetadata: Equatable {
    let statusCode: Int
    let headers: [String: String]

    init(statusCode: Int, headers: [String: String] = [:]) throws {
        guard 100 ... 599 ~= statusCode, headers.count <= 128 else {
            throw DeepgramMeetingTranscriptionError.invalidConfiguration
        }
        var normalizedHeaders: [String: String] = [:]
        for (name, value) in headers {
            let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedName.isEmpty,
                  normalizedName.utf8.count <= 256,
                  normalizedName.utf8.allSatisfy({ byte in
                      byte >= 0x21 && byte <= 0x7E && byte != 0x3A
                  }),
                  value.utf8.count <= 4096,
                  !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else {
                throw DeepgramMeetingTranscriptionError.invalidConfiguration
            }
            normalizedHeaders[normalizedName] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.statusCode = statusCode
        self.headers = normalizedHeaders
    }
}

protocol DeepgramWebSocketResponseMetadataProviding: Sendable {
    func deepgramResponseMetadata() async -> DeepgramWebSocketResponseMetadata?
}

struct DeepgramNova3Configuration {
    let credentialProfileID: UUID
    let endpointingMilliseconds: Int
    let utteranceEndMilliseconds: Int
    let keepAliveInterval: Duration
    let maximumEventBytes: Int

    init(
        credentialProfileID: UUID,
        endpointingMilliseconds: Int = 300,
        utteranceEndMilliseconds: Int = 1000,
        keepAliveInterval: Duration = .seconds(4),
        maximumEventBytes: Int = 1024 * 1024
    ) throws {
        guard 10 ... 5000 ~= endpointingMilliseconds,
              1000 ... 10000 ~= utteranceEndMilliseconds,
              keepAliveInterval >= .seconds(3),
              keepAliveInterval <= .seconds(5),
              1024 ... 4 * 1024 * 1024 ~= maximumEventBytes
        else {
            throw DeepgramMeetingTranscriptionError.invalidConfiguration
        }
        self.credentialProfileID = credentialProfileID
        self.endpointingMilliseconds = endpointingMilliseconds
        self.utteranceEndMilliseconds = utteranceEndMilliseconds
        self.keepAliveInterval = keepAliveInterval
        self.maximumEventBytes = maximumEventBytes
    }
}

final class DeepgramMeetingTranscriptionProvider: MeetingTranscriptionProvider, @unchecked Sendable {
    static let providerID = "deepgram"

    let descriptor: MeetingTranscriptionProviderDescriptor

    private let configuration: DeepgramNova3Configuration
    private let secretResolver: any DeepgramAPIKeyResolving
    private let transportFactory: any STTWebSocketTransportFactory
    private let endpoint: MeetingTranscriptionEndpointSnapshot
    private let selectedModel: MeetingDiscoveredTranscriptionModel
    private let endpointValidator: any MeetingTranscriptionEndpointResolving
    private let nowMilliseconds: @Sendable () -> Int64
    private let makeKeepAliveTicks: @Sendable (Duration) -> AsyncStream<Void>

    init(
        configuration: DeepgramNova3Configuration,
        secretResolver: any DeepgramAPIKeyResolving,
        transportFactory: any STTWebSocketTransportFactory,
        endpoint: MeetingTranscriptionEndpointSnapshot,
        model: MeetingDiscoveredTranscriptionModel,
        endpointValidator: any MeetingTranscriptionEndpointResolving = MeetingTranscriptionEndpointResolutionValidator(),
        nowMilliseconds: @escaping @Sendable () -> Int64 = {
            max(0, Int64(Date().timeIntervalSince1970 * 1000))
        },
        makeKeepAliveTicks: @escaping @Sendable (Duration) -> AsyncStream<Void> = {
            DeepgramMeetingTranscriptionProvider.keepAliveTicks(interval: $0)
        }
    ) throws {
        guard endpoint.providerID == Self.providerID,
              endpoint.variant == .deepgram,
              model.modes.contains(.cloudRealtime)
        else {
            throw DeepgramMeetingTranscriptionError.invalidConfiguration
        }
        self.configuration = configuration
        self.secretResolver = secretResolver
        self.transportFactory = transportFactory
        self.endpoint = endpoint
        selectedModel = model
        self.endpointValidator = endpointValidator
        self.nowMilliseconds = nowMilliseconds
        self.makeKeepAliveTicks = makeKeepAliveTicks
        descriptor = try MeetingTranscriptionDynamicDescriptorFactory.providerDescriptor(
            providerID: Self.providerID,
            displayName: "Deepgram",
            models: [model],
            endpoint: endpoint,
            selectedMode: .cloudRealtime,
            diarizationEnabled: true
        )
    }

    func route(
        languageCodes: [String],
        diarizationEnabled: Bool = true,
        noContentRetention: Bool = true
    ) throws -> MeetingTranscriptionRoute {
        try MeetingTranscriptionRoute(
            providerID: Self.providerID,
            modelID: selectedModel.id,
            languageCodes: languageCodes,
            regionID: endpoint.regionID,
            mode: .cloudRealtime,
            diarizationEnabled: diarizationEnabled,
            retention: noContentRetention ? .none : .providerDefault
        )
    }

    func readiness(for route: MeetingTranscriptionRoute) async -> MeetingTranscriptionReadiness {
        guard (try? validate(route: route)) != nil else { return .unavailable }
        do {
            try await endpointValidator.validate(endpoint)
            _ = try apiKey()
            return .ready
        } catch {
            return (try? MeetingTranscriptionReadiness(
                state: .requiresConfiguration,
                reason: "The Deepgram endpoint or credential is unavailable."
            )) ?? .unavailable
        }
    }

    func makeSession(
        route: MeetingTranscriptionRoute,
        context: any MeetingTrackTranscriptionContext
    ) async throws -> any MeetingTrackTranscriptionSession {
        try validate(route: route)
        try await endpointValidator.validate(endpoint)
        guard context.canonicalSampleRateHertz == 16000, context.channelCount == 1 else {
            throw DeepgramMeetingTranscriptionError.invalidConfiguration
        }
        let contextSnapshot = try MeetingTrackTranscriptionContextSnapshot(
            sessionID: context.sessionID,
            trackID: context.trackID,
            source: context.source,
            canonicalSampleRateHertz: context.canonicalSampleRateHertz,
            channelCount: context.channelCount,
            startedAtMilliseconds: context.startedAtMilliseconds,
            keyterms: context.keyterms
        )
        try Self.validateKeyterms(contextSnapshot.keyterms)
        return try DeepgramMeetingTrackTranscriptionSession(
            route: route,
            context: contextSnapshot,
            configuration: configuration,
            endpoint: endpoint.webSocketURL(path: "/v1/listen"),
            resolveAPIKey: { [secretResolver, configuration] in
                try Self.validatedAPIKey(secretResolver.resolveAPIKey(profileID: configuration.credentialProfileID))
            },
            transport: transportFactory.makeTransport(),
            nowMilliseconds: nowMilliseconds,
            keepAliveTicks: makeKeepAliveTicks(configuration.keepAliveInterval)
        )
    }

    private func validate(route: MeetingTranscriptionRoute) throws {
        try route.validate(against: descriptor)
        guard route.providerID == Self.providerID,
              route.modelID == selectedModel.id,
              route.regionID == endpoint.regionID,
              route.mode == .cloudRealtime,
              route.retention == .none || route.retention == .providerDefault || route.retention == .configurable
        else {
            throw DeepgramMeetingTranscriptionError.invalidRoute
        }
    }

    private func apiKey() throws -> String {
        do {
            return try Self.validatedAPIKey(secretResolver.resolveAPIKey(profileID: configuration.credentialProfileID))
        } catch let error as DeepgramMeetingTranscriptionError {
            throw error
        } catch {
            throw DeepgramMeetingTranscriptionError.credentialUnavailable
        }
    }

    private static func validatedAPIKey(_ data: Data) throws -> String {
        guard !data.isEmpty,
              data.count <= 1024,
              data.allSatisfy({ 0x21 ... 0x7E ~= $0 }),
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else {
            throw DeepgramMeetingTranscriptionError.invalidCredential
        }
        return value
    }

    static func validateKeyterms(_ keyterms: [String]) throws {
        let characterCount = keyterms.reduce(0) { $0 + $1.count }
        let estimatedTokenCount = keyterms.reduce(0) { count, term in
            let wordCount = term.split(whereSeparator: \.isWhitespace).count
            return count + max(wordCount, (term.utf8.count + 2) / 3)
        }
        guard keyterms.count <= 100,
              characterCount <= 2000,
              estimatedTokenCount <= 400,
              Set(keyterms).count == keyterms.count,
              keyterms.allSatisfy({ term in
                  term == term.trimmingCharacters(in: .whitespacesAndNewlines) &&
                      !term.isEmpty && term.count <= 200 &&
                      !term.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
              })
        else {
            throw DeepgramMeetingTranscriptionError.invalidConfiguration
        }
    }

    private static func keepAliveTicks(interval: Duration) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: interval)
                        switch continuation.yield() {
                        case .enqueued,
                             .dropped:
                            break
                        case .terminated:
                            return
                        @unknown default:
                            return
                        }
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
