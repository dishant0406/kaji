import Foundation

final class ElevenLabsScribeMeetingTranscriptionProvider: MeetingTranscriptionProvider, @unchecked Sendable {
    static let providerID = "elevenlabs-scribe"

    let descriptor: MeetingTranscriptionProviderDescriptor

    private let credentialResolver: any ElevenLabsScribeCredentialResolving
    private let httpTransportFactory: any ElevenLabsScribeHTTPTransportFactory
    private let webSocketTransportFactory: any STTWebSocketTransportFactory
    private let batchOptions: ElevenLabsScribeBatchOptions
    private let realtimeOptions: ElevenLabsScribeRealtimeOptions
    private let endpoint: MeetingTranscriptionEndpointSnapshot
    private let selectedModels: [String: MeetingDiscoveredTranscriptionModel]
    private let endpointValidator: any MeetingTranscriptionEndpointResolving
    private let nowMilliseconds: @Sendable () -> Int64
    private let boundary: @Sendable () -> String

    init(
        credentialResolver: any ElevenLabsScribeCredentialResolving,
        httpTransportFactory: any ElevenLabsScribeHTTPTransportFactory,
        webSocketTransportFactory: any STTWebSocketTransportFactory,
        batchOptions: ElevenLabsScribeBatchOptions,
        realtimeOptions: ElevenLabsScribeRealtimeOptions,
        endpoint: MeetingTranscriptionEndpointSnapshot,
        model: MeetingDiscoveredTranscriptionModel,
        models: [MeetingDiscoveredTranscriptionModel]? = nil,
        mode: MeetingTranscriptionMode,
        endpointValidator: any MeetingTranscriptionEndpointResolving = MeetingTranscriptionEndpointResolutionValidator(),
        nowMilliseconds: @escaping @Sendable () -> Int64 = {
            max(0, Int64(Date().timeIntervalSince1970 * 1000))
        },
        boundary: @escaping @Sendable () -> String = {
            "KajiElevenLabs\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        }
    ) throws {
        guard endpoint.providerID == Self.providerID,
              endpoint.variant == .elevenLabsScribe,
              (models ?? [model]).allSatisfy({ !$0.modes.isEmpty })
        else {
            throw ElevenLabsScribeError.invalidConfiguration("dynamic-provider")
        }
        descriptor = try MeetingTranscriptionDynamicDescriptorFactory.providerDescriptor(
            providerID: Self.providerID,
            displayName: "ElevenLabs Scribe",
            models: models ?? [model],
            endpoint: endpoint,
            selectedMode: nil,
            diarizationEnabled: true
        )
        self.credentialResolver = credentialResolver
        self.httpTransportFactory = httpTransportFactory
        self.webSocketTransportFactory = webSocketTransportFactory
        self.batchOptions = batchOptions
        self.realtimeOptions = realtimeOptions
        self.endpoint = endpoint
        selectedModels = Dictionary(uniqueKeysWithValues: (models ?? [model]).map { ($0.id, $0) })
        self.endpointValidator = endpointValidator
        self.nowMilliseconds = nowMilliseconds
        self.boundary = boundary
    }

    func route(
        mode: MeetingTranscriptionMode,
        languageCode: String? = nil,
        diarizationEnabled: Bool = false,
        retention: MeetingTranscriptionDataRetentionClass = .providerDefault
    ) throws -> MeetingTranscriptionRoute {
        guard let model = selectedModels.values.first(where: { $0.modes.contains(mode) }),
              mode == .cloudBatch || mode == .cloudRealtime,
              mode == .cloudBatch || !diarizationEnabled
        else { throw ElevenLabsScribeError.invalidRoute }
        let route = try MeetingTranscriptionRoute(
            providerID: Self.providerID,
            modelID: model.id,
            languageCodes: languageCode.map { [$0] } ?? [],
            regionID: endpoint.regionID,
            mode: mode,
            diarizationEnabled: diarizationEnabled,
            retention: retention
        )
        try validate(route)
        return route
    }

    func readiness(for route: MeetingTranscriptionRoute) async -> MeetingTranscriptionReadiness {
        guard (try? validate(route)) != nil else { return .unavailable }
        do {
            try await endpointValidator.validate(endpoint)
            _ = try await Self.validAPIKey(from: credentialResolver)
            return .ready
        } catch {
            return (try? MeetingTranscriptionReadiness(
                state: .requiresConfiguration,
                reason: "The ElevenLabs-compatible endpoint or credential is unavailable."
            )) ?? .unavailable
        }
    }

    func makeSession(
        route: MeetingTranscriptionRoute,
        context: any MeetingTrackTranscriptionContext
    ) async throws -> any MeetingTrackTranscriptionSession {
        try validate(route)
        try await endpointValidator.validate(endpoint)
        let snapshot = try MeetingTrackTranscriptionContextSnapshot(
            sessionID: context.sessionID,
            trackID: context.trackID,
            source: context.source,
            canonicalSampleRateHertz: context.canonicalSampleRateHertz,
            channelCount: context.channelCount,
            startedAtMilliseconds: context.startedAtMilliseconds,
            keyterms: context.keyterms
        )
        switch route.mode {
        case .cloudBatch:
            try ElevenLabsScribeKeytermPolicy.validateBatch(snapshot.keyterms)
            let transport = httpTransportFactory.makeTransport()
            return try ElevenLabsScribeBatchSession(
                route: route,
                context: snapshot,
                client: ElevenLabsScribeBatchClient(
                    credentialResolver: credentialResolver,
                    transport: transport,
                    options: batchOptions,
                    endpoint: endpoint.restURL(path: "/v1/speech-to-text"),
                    boundary: boundary
                ),
                transport: transport,
                nowMilliseconds: nowMilliseconds
            )
        case .cloudRealtime:
            guard !route.diarizationEnabled else { throw ElevenLabsScribeError.invalidRoute }
            try ElevenLabsScribeKeytermPolicy.validateRealtime(snapshot.keyterms)
            return try ElevenLabsScribeRealtimeSession(
                route: route,
                context: snapshot,
                credentialResolver: credentialResolver,
                transport: webSocketTransportFactory.makeTransport(),
                options: realtimeOptions,
                endpoint: endpoint.webSocketURL(path: "/v1/speech-to-text/realtime"),
                nowMilliseconds: nowMilliseconds
            )
        case .localChunked:
            throw ElevenLabsScribeError.invalidRoute
        }
    }

    private func validate(_ route: MeetingTranscriptionRoute) throws {
        try route.validate(against: descriptor)
        guard route.providerID == Self.providerID,
              let model = selectedModels[route.modelID],
              model.modes.contains(route.mode),
              route.regionID == endpoint.regionID,
              route.languageCodes.count <= 1,
              route.retention == .providerDefault || route.retention == .none || route.retention == .configurable,
              route.mode == .cloudBatch || !route.diarizationEnabled
        else {
            throw ElevenLabsScribeError.invalidRoute
        }
    }

    static func validAPIKey(from resolver: any ElevenLabsScribeCredentialResolving) async throws -> String {
        let data: Data
        do {
            data = try await resolver.resolveAPIKey()
        } catch let error as ElevenLabsScribeError {
            throw error
        } catch {
            throw ElevenLabsScribeError.credentialUnavailable
        }
        guard 1 ... 1024 ~= data.count,
              let value = String(data: data, encoding: .utf8),
              value.utf8.count == data.count,
              value.utf8.allSatisfy({ 0x21 ... 0x7E ~= $0 })
        else {
            throw ElevenLabsScribeError.invalidCredential
        }
        return value
    }
}

actor ElevenLabsScribeBatchSession: MeetingTrackTranscriptionSession {
    private enum State {
        case idle
        case started
        case finished
        case cancelled
    }

    nonisolated let events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>

    private let route: MeetingTranscriptionRoute
    private let context: MeetingTrackTranscriptionContextSnapshot
    private let client: ElevenLabsScribeBatchClient
    private let transport: any ElevenLabsScribeHTTPTransporting
    private let nowMilliseconds: @Sendable () -> Int64
    private let eventChannel: MeetingTranscriptionProviderEventChannel
    private var state = State.idle
    private var sequenceNumber: Int64 = 0

    init(
        route: MeetingTranscriptionRoute,
        context: MeetingTrackTranscriptionContextSnapshot,
        client: ElevenLabsScribeBatchClient,
        transport: any ElevenLabsScribeHTTPTransporting,
        nowMilliseconds: @escaping @Sendable () -> Int64
    ) {
        self.route = route
        self.context = context
        self.client = client
        self.transport = transport
        self.nowMilliseconds = nowMilliseconds
        let eventChannel = MeetingTranscriptionProviderEventChannel()
        self.eventChannel = eventChannel
        events = eventChannel.events
    }

    func start() async throws {
        guard state == .idle else { throw ElevenLabsScribeError.invalidState }
        state = .started
        try emitSession(.starting)
        try emitSession(.ready)
    }

    func submit(_ packet: MeetingNormalizedAudioPacket) async throws {
        guard state == .started else { throw ElevenLabsScribeError.invalidState }
        if packet.isEndOfStream {
            try await finish()
            return
        }
        do {
            try Task.checkCancellation()
            let result = try await client.submit(ElevenLabsScribeBatchRequest(
                route: route,
                context: context,
                packet: packet,
                delivery: .synchronous
            ))
            guard state == .started else { throw CancellationError() }
            guard case let .transcript(transcript) = result else {
                throw ElevenLabsScribeError.malformedResponse
            }
            try eventChannel.send(.final(finalEvent(transcript: transcript, packet: packet)))
        } catch is CancellationError {
            let error = ElevenLabsScribeError.providerFailure(
                code: "cancelled",
                classification: .cancelled,
                retryAfterMilliseconds: nil
            )
            try? emitFailure(error, packet: packet)
            throw error
        } catch let error as ElevenLabsScribeError {
            if error.failureClassification == .rateLimited {
                try? emitRateLimit(error, packet: packet)
            }
            try? emitFailure(error, packet: packet)
            throw error
        } catch {
            let wrapped = ElevenLabsScribeError.providerFailure(
                code: "batch-failure",
                classification: .permanent,
                retryAfterMilliseconds: nil
            )
            try? emitFailure(wrapped, packet: packet)
            throw wrapped
        }
    }

    func finish() async throws {
        guard state == .started else {
            if state == .finished || state == .cancelled {
                return
            }
            throw ElevenLabsScribeError.invalidState
        }
        try emitSession(.draining)
        state = .finished
        try emitSession(.completed)
        eventChannel.finish()
    }

    func cancel() async {
        guard state != .finished, state != .cancelled else { return }
        state = .cancelled
        await transport.cancel()
        try? emitSession(.cancelled)
        eventChannel.finish()
    }

    private func finalEvent(
        transcript: ElevenLabsScribeTranscript,
        packet: MeetingNormalizedAudioPacket
    ) throws -> MeetingTranscriptionFinalEvent {
        let mappedWords = try transcript.words.enumerated().compactMap { index, word in
            try normalizedWord(word, index: index, transcript: transcript, packet: packet)
        }
        let speakerIDs = Set(mappedWords.compactMap(\.speakerID))
        guard speakerIDs.count <= 32,
              route.diarizationEnabled || speakerIDs.isEmpty
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        let speaker = try speakerIDs.count == 1 ? speakerIDs.first.map {
            try MeetingNormalizedSpeaker(id: $0, label: Self.speakerLabel($0))
        } : nil
        let confidenceValues = mappedWords.compactMap(\.confidence)
        let confidence = confidenceValues.isEmpty ? nil : confidenceValues.reduce(0, +) / Double(confidenceValues.count)
        let emittedAt = nowMilliseconds()
        let utterance = try MeetingTranscriptionUtterance(
            id: packet.operationID,
            revision: 0,
            sampleRange: packet.sampleRange,
            text: transcript.text,
            confidence: confidence,
            words: mappedWords,
            speaker: speaker,
            language: MeetingNormalizedLanguage(
                code: transcript.languageCode,
                confidence: transcript.languageProbability
            ),
            createdAtMilliseconds: max(context.startedAtMilliseconds, emittedAt)
        )
        return try MeetingTranscriptionFinalEvent(
            context: eventContext(
                eventID: packet.operationID,
                operationID: packet.operationID,
                epoch: packet.providerEpoch,
                emittedAtMilliseconds: emittedAt
            ),
            utterance: utterance
        )
    }

    private func normalizedWord(
        _ word: ElevenLabsScribeWord,
        index: Int,
        transcript: ElevenLabsScribeTranscript,
        packet: MeetingNormalizedAudioPacket
    ) throws -> MeetingNormalizedWord? {
        guard word.kind != .spacing else { return nil }
        guard let startSeconds = word.startSeconds,
              let endSeconds = word.endSeconds
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        let startOffset = Int64((startSeconds * 16000).rounded())
        let endOffset = Int64((endSeconds * 16000).rounded())
        let startFrame = packet.sampleRange.startFrame + startOffset
        let endFrame = packet.sampleRange.startFrame + endOffset
        guard startFrame >= packet.sampleRange.startFrame,
              endFrame > startFrame,
              endFrame <= packet.sampleRange.endFrame
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        return try MeetingNormalizedWord(
            id: ElevenLabsScribeIdentity.derivedUUID(namespace: packet.operationID, index: UInt64(index + 1)),
            text: word.text,
            sampleRange: MeetingCanonicalSampleRange(
                startFrame: startFrame,
                endFrame: endFrame,
                sampleRateHertz: 16000
            ),
            confidence: exp(word.logProbability),
            speakerID: word.speakerID,
            languageCode: transcript.languageCode
        )
    }

    private static func speakerLabel(_ id: String) -> String {
        guard let suffix = id.split(separator: "_").last,
              let number = Int(suffix)
        else {
            return id
        }
        return "Speaker \(number + 1)"
    }

    private func emitSession(_ sessionState: MeetingTranscriptionSessionState) throws {
        try eventChannel.send(.session(MeetingTranscriptionSessionEvent(
            context: eventContext(
                eventID: UUID(),
                operationID: nil,
                epoch: .initial,
                emittedAtMilliseconds: nowMilliseconds()
            ),
            state: sessionState
        )))
    }

    private func emitRateLimit(
        _ error: ElevenLabsScribeError,
        packet: MeetingNormalizedAudioPacket
    ) throws {
        try eventChannel.send(.rateLimit(MeetingTranscriptionRateLimitEvent(
            context: eventContext(
                eventID: UUID(),
                operationID: packet.operationID,
                epoch: packet.providerEpoch,
                emittedAtMilliseconds: nowMilliseconds()
            ),
            scope: "elevenlabs-scribe",
            retryAfterMilliseconds: error.retryAfterMilliseconds
        )))
    }

    private func emitFailure(
        _ error: ElevenLabsScribeError,
        packet: MeetingNormalizedAudioPacket
    ) throws {
        try eventChannel.send(.failure(MeetingTranscriptionFailureEvent(
            context: eventContext(
                eventID: UUID(),
                operationID: packet.operationID,
                epoch: packet.providerEpoch,
                emittedAtMilliseconds: nowMilliseconds()
            ),
            code: error.code,
            message: error.safeMessage,
            classification: error.failureClassification,
            retryAfterMilliseconds: error.retryAfterMilliseconds
        )))
    }

    private func eventContext(
        eventID: UUID,
        operationID: UUID?,
        epoch: MeetingProviderEpoch,
        emittedAtMilliseconds: Int64
    ) throws -> MeetingTranscriptionEventContext {
        defer { sequenceNumber += 1 }
        return try MeetingTranscriptionEventContext(
            eventID: eventID,
            operationID: operationID,
            sessionID: context.sessionID,
            trackID: context.trackID,
            source: context.source,
            providerEpoch: epoch,
            sequenceNumber: sequenceNumber,
            emittedAtMilliseconds: max(0, emittedAtMilliseconds)
        )
    }
}
