import CryptoKit
import Foundation

final class AssemblyAIMeetingTranscriptionProvider: MeetingTranscriptionProvider, @unchecked Sendable {
    static let providerID = "assemblyai"

    let descriptor: MeetingTranscriptionProviderDescriptor

    private let secretResolver: any AssemblyAISecretResolving
    private let transportFactory: any STTWebSocketTransportFactory
    private let configuration: AssemblyAIStreamingSessionConfiguration
    private let endpoint: MeetingTranscriptionEndpointSnapshot
    private let selectedModel: MeetingDiscoveredTranscriptionModel
    private let endpointValidator: any MeetingTranscriptionEndpointResolving
    private let nowMilliseconds: @Sendable () -> Int64
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        secretResolver: any AssemblyAISecretResolving,
        transportFactory: any STTWebSocketTransportFactory,
        configuration: AssemblyAIStreamingSessionConfiguration,
        endpoint: MeetingTranscriptionEndpointSnapshot,
        model: MeetingDiscoveredTranscriptionModel,
        endpointValidator: any MeetingTranscriptionEndpointResolving = MeetingTranscriptionEndpointResolutionValidator(),
        nowMilliseconds: @escaping @Sendable () -> Int64 = {
            max(0, Int64(Date().timeIntervalSince1970 * 1000))
        },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) throws {
        guard endpoint.providerID == Self.providerID,
              endpoint.variant == .assemblyAIStreamingV3,
              model.modes.contains(.cloudRealtime)
        else {
            throw AssemblyAIMeetingTranscriptionError.invalidConfiguration
        }
        descriptor = try MeetingTranscriptionDynamicDescriptorFactory.providerDescriptor(
            providerID: Self.providerID,
            displayName: "AssemblyAI",
            models: [model],
            endpoint: endpoint,
            selectedMode: .cloudRealtime,
            diarizationEnabled: true
        )
        self.secretResolver = secretResolver
        self.transportFactory = transportFactory
        self.configuration = configuration
        self.endpoint = endpoint
        selectedModel = model
        self.endpointValidator = endpointValidator
        self.nowMilliseconds = nowMilliseconds
        self.sleep = sleep
    }

    func route(
        languageCodes: [String] = [],
        diarizationEnabled: Bool = false,
        retention: MeetingTranscriptionDataRetentionClass = .providerDefault
    ) throws -> MeetingTranscriptionRoute {
        let route = try MeetingTranscriptionRoute(
            providerID: Self.providerID,
            modelID: selectedModel.id,
            languageCodes: languageCodes,
            regionID: endpoint.regionID,
            mode: .cloudRealtime,
            diarizationEnabled: diarizationEnabled,
            retention: retention
        )
        try validate(route: route)
        return route
    }

    func readiness(for route: MeetingTranscriptionRoute) async -> MeetingTranscriptionReadiness {
        guard (try? validate(route: route)) != nil else { return .unavailable }
        do {
            try await endpointValidator.validate(endpoint)
            _ = try await secretResolver.resolveCredential()
            return .ready
        } catch {
            return (try? MeetingTranscriptionReadiness(
                state: .requiresConfiguration,
                reason: "The AssemblyAI-compatible endpoint or credential is unavailable."
            )) ?? .unavailable
        }
    }

    func makeSession(
        route: MeetingTranscriptionRoute,
        context: any MeetingTrackTranscriptionContext
    ) async throws -> any MeetingTrackTranscriptionSession {
        try validate(route: route)
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
        guard snapshot.canonicalSampleRateHertz == AssemblyAIStreamingSessionConfiguration.sampleRateHertz,
              snapshot.channelCount == AssemblyAIStreamingSessionConfiguration.channelCount,
              snapshot.keyterms.count <= 100
        else {
            throw AssemblyAIMeetingTranscriptionError.invalidConfiguration
        }
        let credential: AssemblyAIStreamingCredential
        do {
            credential = try await secretResolver.resolveCredential()
        } catch let error as AssemblyAIMeetingTranscriptionError {
            throw error
        } catch {
            throw AssemblyAIMeetingTranscriptionError.credentialUnavailable
        }
        let request = try configuration.makeRequest(
            route: route,
            context: snapshot,
            credential: credential,
            endpoint: endpoint.webSocketURL(path: "/v3/ws")
        )
        return AssemblyAIMeetingTrackTranscriptionSession(
            route: route,
            context: snapshot,
            request: request,
            transport: transportFactory.makeTransport(),
            configuration: configuration,
            nowMilliseconds: nowMilliseconds,
            sleep: sleep
        )
    }

    private func validate(route: MeetingTranscriptionRoute) throws {
        do {
            try route.validate(against: descriptor)
            try configuration.privacy.validate(retention: route.retention)
        } catch let error as AssemblyAIMeetingTranscriptionError {
            throw error
        } catch {
            throw AssemblyAIMeetingTranscriptionError.invalidRoute
        }
        guard route.providerID == Self.providerID,
              route.modelID == selectedModel.id,
              route.regionID == endpoint.regionID,
              route.mode == .cloudRealtime,
              route.diarizationEnabled || configuration.maximumSpeakers == nil
        else {
            throw AssemblyAIMeetingTranscriptionError.invalidRoute
        }
    }
}

actor AssemblyAIMeetingTrackTranscriptionSession: MeetingTrackTranscriptionSession {
    private enum State {
        case idle
        case connecting
        case ready
        case draining
        case completed
        case failed
        case cancelled
    }

    private struct SubmittedOperation {
        let id: UUID
        let streamStartFrame: Int64
        let streamEndFrame: Int64
        let canonicalStartFrame: Int64
        let epoch: MeetingProviderEpoch
    }

    private struct PendingOperation {
        let id: UUID
        let bufferStartFrame: Int64
        let bufferEndFrame: Int64
        let canonicalStartFrame: Int64
        let epoch: MeetingProviderEpoch
    }

    private struct StreamRange {
        let startFrame: Int64
        let endFrame: Int64
    }

    private struct TurnRecord {
        let id: UUID
        let operationID: UUID?
        let epoch: MeetingProviderEpoch
        var revision: Int
        var signature: Data
        var utterance: MeetingTranscriptionUtterance
        let streamWordRanges: [StreamRange]
        var isFinal: Bool
        var speakerRevisionApplied: Bool
    }

    nonisolated let events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>

    private let route: MeetingTranscriptionRoute
    private let context: MeetingTrackTranscriptionContextSnapshot
    private let request: URLRequest
    private let transport: any STTWebSocketTransporting
    private let configuration: AssemblyAIStreamingSessionConfiguration
    private let nowMilliseconds: @Sendable () -> Int64
    private let sleep: @Sendable (Duration) async throws -> Void
    private let eventChannel: MeetingTranscriptionProviderEventChannel
    private var state = State.idle
    private var sequenceNumber: Int64 = 0
    private var providerSessionID: String?
    private var highestTurnOrder = -1
    private var submittedOperations: [SubmittedOperation] = []
    private var submittedStreamFrameCount: Int64 = 0
    private var pendingAudio = Data()
    private var pendingOperations: [PendingOperation] = []
    private var turns: [Int: TurnRecord] = [:]
    private var eventLoopTask: Task<Void, Never>?
    private var rotationWarningTask: Task<Void, Never>?
    private var didEmitTerminalFailure = false
    private var terminalError: AssemblyAIMeetingTranscriptionError?

    init(
        route: MeetingTranscriptionRoute,
        context: MeetingTrackTranscriptionContextSnapshot,
        request: URLRequest,
        transport: any STTWebSocketTransporting,
        configuration: AssemblyAIStreamingSessionConfiguration,
        nowMilliseconds: @escaping @Sendable () -> Int64,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.route = route
        self.context = context
        self.request = request
        self.transport = transport
        self.configuration = configuration
        self.nowMilliseconds = nowMilliseconds
        self.sleep = sleep
        let eventChannel = MeetingTranscriptionProviderEventChannel()
        self.eventChannel = eventChannel
        events = eventChannel.events
    }

    func start() async throws {
        guard state == .idle else { throw AssemblyAIMeetingTranscriptionError.invalidState }
        state = .connecting
        emitSession(.starting)
        let transportEvents = await transport.events()
        eventLoopTask = Task { [weak self] in
            for await event in transportEvents {
                guard let self else { return }
                await self.handle(event)
            }
        }
        do {
            try await transport.connect(request: request)
        } catch {
            await failForTransport(error)
            throw sanitize(error)
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(configuration.beginTimeoutSeconds))
        while state == .connecting, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        if state == .ready { return }
        if state == .cancelled { throw AssemblyAIMeetingTranscriptionError.cancelled }
        if state == .failed { throw terminalError ?? AssemblyAIMeetingTranscriptionError.serviceUnavailable }
        terminalError = .timedOut
        emitFailure(code: "begin-timeout", classification: .transient)
        state = .failed
        await transport.cancel()
        finishEventStream()
        throw AssemblyAIMeetingTranscriptionError.timedOut
    }

    func submit(_ packet: MeetingNormalizedAudioPacket) async throws {
        guard state == .ready else { throw AssemblyAIMeetingTranscriptionError.invalidState }
        if packet.isEndOfStream {
            try await finish()
            return
        }
        guard packet.sessionID == context.sessionID,
              packet.trackID == context.trackID,
              packet.source == context.source,
              packet.sampleRateHertz == AssemblyAIStreamingSessionConfiguration.sampleRateHertz,
              packet.channelCount == AssemblyAIStreamingSessionConfiguration.channelCount,
              packet.encoding == .pcmSigned16LittleEndian,
              1 ... Int64(AssemblyAIStreamingSessionConfiguration.maximumAudioFrames) ~= packet.sampleRange.frameCount,
              Int64(packet.bytes.count) == packet.sampleRange.frameCount * 2
        else {
            throw AssemblyAIMeetingTranscriptionError.invalidPacket
        }
        appendPending(packet)
        try await flushReadyAudio()
    }

    private func appendPending(_ packet: MeetingNormalizedAudioPacket) {
        let bufferStartFrame = Int64(pendingAudio.count / 2)
        pendingAudio.append(packet.bytes)
        pendingOperations.append(PendingOperation(
            id: packet.operationID,
            bufferStartFrame: bufferStartFrame,
            bufferEndFrame: bufferStartFrame + packet.sampleRange.frameCount,
            canonicalStartFrame: packet.sampleRange.startFrame,
            epoch: packet.providerEpoch
        ))
    }

    private func flushReadyAudio() async throws {
        let minimumFrames = Int64(AssemblyAIStreamingSessionConfiguration.minimumAudioFrames)
        let maximumFrames = Int64(AssemblyAIStreamingSessionConfiguration.maximumAudioFrames)
        while Int64(pendingAudio.count / 2) >= minimumFrames {
            let availableFrames = Int64(pendingAudio.count / 2)
            let frameCount = availableFrames <= maximumFrames ? availableFrames : availableFrames - minimumFrames
            try await sendPendingAudio(frameCount: frameCount, wireFrameCount: frameCount)
        }
    }

    private func flushResidualAudio() async throws {
        let frameCount = Int64(pendingAudio.count / 2)
        guard frameCount > 0 else { return }
        let wireFrameCount = max(frameCount, Int64(AssemblyAIStreamingSessionConfiguration.minimumAudioFrames))
        try await sendPendingAudio(frameCount: frameCount, wireFrameCount: wireFrameCount)
    }

    private func sendPendingAudio(frameCount: Int64, wireFrameCount: Int64) async throws {
        let maximumFrames = Int64(AssemblyAIStreamingSessionConfiguration.maximumAudioFrames)
        guard frameCount > 0,
              frameCount <= wireFrameCount,
              Int64(AssemblyAIStreamingSessionConfiguration.minimumAudioFrames) ... maximumFrames ~= wireFrameCount
        else {
            throw AssemblyAIMeetingTranscriptionError.invalidState
        }
        var bytes = pendingAudio.prefix(Int(frameCount * 2))
        if wireFrameCount > frameCount {
            bytes.append(Data(repeating: 0, count: Int((wireFrameCount - frameCount) * 2)))
        }
        do {
            try await transport.send(.binary(Data(bytes)))
        } catch {
            await failForTransport(error)
            throw sanitize(error)
        }
        let streamStartFrame = submittedStreamFrameCount
        for operation in pendingOperations {
            let startFrame = max(0, operation.bufferStartFrame)
            let endFrame = min(frameCount, operation.bufferEndFrame)
            guard endFrame > startFrame else { continue }
            submittedOperations.append(SubmittedOperation(
                id: operation.id,
                streamStartFrame: streamStartFrame + startFrame,
                streamEndFrame: streamStartFrame + endFrame,
                canonicalStartFrame: operation.canonicalStartFrame + startFrame - operation.bufferStartFrame,
                epoch: operation.epoch
            ))
        }
        submittedStreamFrameCount += wireFrameCount
        pendingAudio.removeFirst(Int(frameCount * 2))
        pendingOperations = pendingOperations.compactMap { operation in
            guard operation.bufferEndFrame > frameCount else { return nil }
            let consumedFrames = max(0, frameCount - operation.bufferStartFrame)
            return PendingOperation(
                id: operation.id,
                bufferStartFrame: max(0, operation.bufferStartFrame - frameCount),
                bufferEndFrame: operation.bufferEndFrame - frameCount,
                canonicalStartFrame: operation.canonicalStartFrame + consumedFrames,
                epoch: operation.epoch
            )
        }
    }

    func updateConfiguration(_ update: AssemblyAIStreamingConfigurationUpdate) async throws {
        guard state == .ready else {
            throw AssemblyAIMeetingTranscriptionError.invalidState
        }
        let data = try JSONEncoder().encode(update)
        guard let text = String(data: data, encoding: .utf8), data.count <= 32 * 1024 else {
            throw AssemblyAIMeetingTranscriptionError.invalidConfiguration
        }
        try await transport.send(.text(text))
    }

    func finish() async throws {
        if state == .completed || state == .cancelled { return }
        guard state == .ready else {
            if state == .failed { throw AssemblyAIMeetingTranscriptionError.serviceUnavailable }
            throw AssemblyAIMeetingTranscriptionError.invalidState
        }
        state = .draining
        emitSession(.draining)
        do {
            try await flushResidualAudio()
            try await transport.send(.text("{\"type\":\"Terminate\"}"))
        } catch {
            await failForTransport(error)
            throw sanitize(error)
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(configuration.terminationTimeoutSeconds))
        while state == .draining, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        if state == .completed { return }
        if state == .cancelled { throw AssemblyAIMeetingTranscriptionError.cancelled }
        if state == .failed { throw AssemblyAIMeetingTranscriptionError.serviceUnavailable }
        emitFailure(code: "termination-timeout", classification: .transient)
        state = .failed
        await transport.cancel()
        finishEventStream()
        throw AssemblyAIMeetingTranscriptionError.timedOut
    }

    func cancel() async {
        guard state != .completed, state != .cancelled else { return }
        state = .cancelled
        rotationWarningTask?.cancel()
        eventLoopTask?.cancel()
        await transport.cancel()
        emitSession(.cancelled)
        finishEventStream()
    }

    private func handle(_ event: STTWebSocketEvent) async {
        switch event {
        case let .message(.text(text)):
            await handle(text)
        case .message(.binary):
            await failProtocol(.malformedResponse)
        case let .failed(error):
            await failForTransport(error)
        case let .closed(code):
            await handleClose(code: code)
        case .stateChanged,
             .pong:
            break
        }
    }

    private func handle(_ text: String) async {
        do {
            let message = try AssemblyAIStreamingWireDecoder.decode(text, maximumBytes: configuration.maximumInboundFrameBytes)
            switch message {
            case let .begin(begin):
                try handleBegin(begin)
            case let .turn(turn):
                try handleTurn(turn, signature: Data(SHA256.hash(data: Data(text.utf8))))
            case let .speakerRevision(revisions):
                try handleSpeakerRevisions(revisions)
            case let .termination(termination):
                try handleTermination(termination)
            case let .error(error):
                await handleServerError(error)
            case .configurationUpdate:
                break
            case .speechStarted:
                break
            }
        } catch let error as AssemblyAIMeetingTranscriptionError {
            await failProtocol(error)
        } catch {
            await failProtocol(.malformedResponse)
        }
    }

    private func handleBegin(_ begin: AssemblyAIStreamingBegin) throws {
        guard state == .connecting,
              providerSessionID == nil,
              UUID(uuidString: begin.id) != nil,
              begin.expiresAt >= 0,
              begin.expiresAt <= nowMilliseconds() / 1000 + Int64(AssemblyAIStreamingSessionConfiguration.maximumSessionSeconds + 60),
              begin.configuration?.model == nil || begin.configuration?.model == route.modelID,
              begin.configuration?.speakerLabels == nil || begin.configuration?.speakerLabels == route.diarizationEnabled
        else {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
        providerSessionID = begin.id.lowercased()
        state = .ready
        emitSession(.ready)
        scheduleRotationWarning(expiresAtSeconds: begin.expiresAt)
    }

    private func handleTurn(_ turn: AssemblyAIStreamingTurn, signature: Data) throws {
        guard state == .ready || state == .draining,
              0 ... 1_000_000 ~= turn.turnOrder,
              turn.endOfTurnConfidence.isFinite,
              0 ... 1 ~= turn.endOfTurnConfidence,
              turn.languageConfidence.map({ $0.isFinite && 0 ... 1 ~= $0 }) ?? true,
              turn.languageCode.map(MeetingTranscriptionValidation.isValidLanguageCode) ?? true
        else {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
        if turn.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard turn.words.isEmpty else { throw AssemblyAIMeetingTranscriptionError.malformedResponse }
            return
        }
        if turn.turnOrder < highestTurnOrder {
            emitWarning(
                code: "out-of-order-turn",
                message: "AssemblyAI delivered an out-of-order turn that was ignored.",
                recoverable: true
            )
            return
        }
        if let existing = turns[turn.turnOrder] {
            if existing.signature == signature || existing.isFinal { return }
        } else {
            highestTurnOrder = turn.turnOrder
        }
        let ranges = try sampleRanges(for: turn.words)
        let sampleRange = ranges.canonical
        let operation = operation(for: ranges.stream)
        guard operation != nil else {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
        let revision = (turns[turn.turnOrder]?.revision ?? -1) + 1
        let utteranceID = turns[turn.turnOrder]?.id ?? deterministicUUID(
            "turn|\(context.sessionID.uuidString)|\(context.trackID.uuidString)|\(turn.turnOrder)|\(operation?.id.uuidString ?? "none")|" +
                "\(sampleRange.startFrame)-\(sampleRange.endFrame)"
        )
        let words = try turn.words.enumerated().map { index, word in
            try normalizedWord(word, utteranceID: utteranceID, index: index, utteranceRange: sampleRange)
        }
        let speaker = try turn.speakerLabel.map(normalizedSpeaker)
        let language = try turn.languageCode.map {
            try MeetingNormalizedLanguage(code: $0, confidence: turn.languageConfidence)
        }
        let confidence = words.isEmpty ? nil : words.compactMap(\.confidence).reduce(0, +) / Double(words.count)
        let utterance = try MeetingTranscriptionUtterance(
            id: utteranceID,
            revision: revision,
            sampleRange: sampleRange,
            text: turn.transcript,
            confidence: confidence,
            words: words,
            speaker: speaker,
            language: language,
            createdAtMilliseconds: max(context.startedAtMilliseconds, nowMilliseconds())
        )
        let isFinal = turn.endOfTurn && turn.turnIsFormatted
        let epoch = operation?.epoch ?? turns[turn.turnOrder]?.epoch ?? .initial
        let eventContext = try makeEventContext(
            eventID: deterministicUUID("turn-event|\(utteranceID.uuidString)|\(revision)|\(signature.base64EncodedString())"),
            operationID: operation?.id ?? turns[turn.turnOrder]?.operationID,
            providerEpoch: epoch
        )
        if isFinal {
            eventChannel.send(.final(MeetingTranscriptionFinalEvent(context: eventContext, utterance: utterance)))
        } else {
            eventChannel.send(.partial(MeetingTranscriptionPartialEvent(context: eventContext, utterance: utterance)))
        }
        turns[turn.turnOrder] = TurnRecord(
            id: utteranceID,
            operationID: operation?.id ?? turns[turn.turnOrder]?.operationID,
            epoch: epoch,
            revision: revision,
            signature: signature,
            utterance: utterance,
            streamWordRanges: turn.words.map { StreamRange(startFrame: $0.start * 16, endFrame: $0.end * 16) },
            isFinal: isFinal,
            speakerRevisionApplied: false
        )
        if isFinal {
            submittedOperations.removeAll { $0.streamEndFrame <= ranges.stream.endFrame }
        }
    }

    private func handleSpeakerRevisions(_ revisions: [AssemblyAIStreamingSpeakerRevision]) throws {
        guard state == .draining,
              route.diarizationEnabled,
              revisions.count <= 10000,
              Set(revisions.map(\.turnOrder)).count == revisions.count
        else {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
        for revision in revisions {
            guard var record = turns[revision.turnOrder], record.isFinal, !record.speakerRevisionApplied,
                  revision.words.count == record.utterance.words.count
            else {
                throw AssemblyAIMeetingTranscriptionError.malformedResponse
            }
            let revisedWords = try zip(zip(record.utterance.words, record.streamWordRanges), revision.words).map { pair, revised in
                let (original, streamRange) = pair
                guard revised.start >= 0,
                      revised.end > revised.start,
                      revised.end <= 10_800_000,
                      original.text == revised.text,
                      revised.start * 16 == streamRange.startFrame,
                      revised.end * 16 == streamRange.endFrame
                else {
                    throw AssemblyAIMeetingTranscriptionError.malformedResponse
                }
                return try MeetingNormalizedWord(
                    id: original.id,
                    text: original.text,
                    sampleRange: original.sampleRange,
                    confidence: original.confidence,
                    speakerID: normalizedSpeakerID(revised.speaker),
                    languageCode: original.languageCode
                )
            }
            let eventContext = try makeEventContext(
                eventID: deterministicUUID("speaker-revision|\(record.id.uuidString)|\(record.utterance.revision + 1)"),
                operationID: record.operationID,
                providerEpoch: record.epoch
            )
            try eventChannel.send(.metadataAmendment(MeetingTranscriptionMetadataAmendmentEvent(
                context: eventContext,
                utteranceID: record.id,
                expectedRevision: record.utterance.revision,
                words: revisedWords,
                speaker: revision.speakerLabel.map(normalizedSpeaker)
            )))
            record.speakerRevisionApplied = true
            turns[revision.turnOrder] = record
        }
    }

    private func handleTermination(_ termination: AssemblyAIStreamingTermination) throws {
        guard state == .draining,
              0 ... Int64(AssemblyAIStreamingSessionConfiguration.maximumSessionSeconds) ~= termination.audioDurationSeconds,
              0 ... Int64(AssemblyAIStreamingSessionConfiguration.maximumSessionSeconds + 60) ~= termination.sessionDurationSeconds
        else {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
        let eventContext = try makeEventContext(eventID: UUID(), operationID: nil, providerEpoch: .initial)
        let metric = try MeetingTranscriptionUsageMetric(
            billingUnit: "streaming-session-seconds",
            quantity: termination.sessionDurationSeconds
        )
        try eventChannel.send(.usage(MeetingTranscriptionUsageEvent(context: eventContext, metrics: [metric])))
        state = .completed
        rotationWarningTask?.cancel()
        emitSession(.completed)
        finishEventStream()
    }

    private func handleServerError(_ error: AssemblyAIStreamingServerError) async {
        let classification: MeetingTranscriptionFailureClassification
        let code: String
        switch error.errorCode {
        case 401,
             1008:
            classification = .authentication
            code = "authentication-failed"
        case 429,
             3009:
            classification = .rateLimited
            code = "rate-limited"
        case 3008:
            emitWarning(
                code: "session-rotation-required",
                message: "The AssemblyAI streaming session reached its rotation limit.",
                recoverable: true
            )
            classification = .unavailable
            code = "session-expired"
        case 3006,
             3007:
            classification = .invalidRequest
            code = "stream-rejected"
        default:
            classification = .transient
            code = "provider-error"
        }
        emitFailure(code: code, classification: classification)
        switch classification {
        case .authentication,
             .authorization:
            terminalError = .authenticationFailed
        case .rateLimited:
            terminalError = .rateLimited
        default:
            terminalError = .serviceUnavailable
        }
        state = .failed
        await transport.cancel()
        finishEventStream()
    }

    private func handleClose(code: Int?) async {
        if state == .completed || state == .cancelled || state == .failed { return }
        if code == 1008 {
            emitFailure(code: "authentication-failed", classification: .authentication)
            terminalError = .authenticationFailed
        } else if code == 401 {
            emitFailure(code: "authentication-failed", classification: .authentication)
            terminalError = .authenticationFailed
        } else if code == 3009 || code == 429 {
            emitFailure(code: "rate-limited", classification: .rateLimited)
            terminalError = .rateLimited
        } else if code == 3008 {
            emitWarning(
                code: "session-rotation-required",
                message: "The AssemblyAI streaming session reached its rotation limit.",
                recoverable: true
            )
            emitFailure(code: "session-expired", classification: .unavailable)
            terminalError = .serviceUnavailable
        } else {
            emitFailure(code: "connection-closed", classification: .transient)
            terminalError = .serviceUnavailable
        }
        state = .failed
        finishEventStream()
    }

    private func failProtocol(_ error: AssemblyAIMeetingTranscriptionError) async {
        guard state != .completed, state != .cancelled, state != .failed else { return }
        let code = error == .responseTooLarge ? "response-too-large" : "malformed-provider-response"
        emitFailure(code: code, classification: .invalidRequest)
        terminalError = error
        state = .failed
        await transport.cancel()
        finishEventStream()
    }

    private func failForTransport(_ error: Error) async {
        guard state != .completed, state != .cancelled, state != .failed else { return }
        let sanitized = sanitize(error)
        let classification: MeetingTranscriptionFailureClassification = sanitized == .cancelled ? .cancelled : .transient
        emitFailure(code: "connection-failed", classification: classification)
        terminalError = sanitized
        state = sanitized == .cancelled ? .cancelled : .failed
        await transport.cancel()
        finishEventStream()
    }

    private func sanitize(_ error: Error) -> AssemblyAIMeetingTranscriptionError {
        if error is CancellationError { return .cancelled }
        if let error = error as? AssemblyAIMeetingTranscriptionError { return error }
        if let error = error as? STTNetworkError {
            switch error {
            case .responseTooLarge: return .responseTooLarge
            case .timedOut: return .timedOut
            case .cancelled: return .cancelled
            case .invalidConfiguration,
                 .invalidResponse,
                 .connectionFailed,
                 .protocolViolation: return .serviceUnavailable
            }
        }
        return .serviceUnavailable
    }

    private func sampleRanges(
        for words: [AssemblyAIStreamingWord]
    ) throws -> (stream: StreamRange, canonical: MeetingCanonicalSampleRange) {
        guard !words.isEmpty,
              words.allSatisfy({
                  $0.start >= 0 && $0.end > $0.start && $0.end <= 10_800_000 && $0.confidence.isFinite && 0 ... 1 ~= $0.confidence
              }),
              let start = words.map(\.start).min(),
              let end = words.map(\.end).max()
        else {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
        let streamRange = StreamRange(startFrame: start * 16, endFrame: end * 16)
        let canonicalRange = try MeetingCanonicalSampleRange(
            startFrame: canonicalFrame(for: streamRange.startFrame, preferPreviousBoundary: false),
            endFrame: canonicalFrame(for: streamRange.endFrame, preferPreviousBoundary: true),
            sampleRateHertz: AssemblyAIStreamingSessionConfiguration.sampleRateHertz
        )
        return (stream: streamRange, canonical: canonicalRange)
    }

    private func normalizedWord(
        _ word: AssemblyAIStreamingWord,
        utteranceID: UUID,
        index: Int,
        utteranceRange: MeetingCanonicalSampleRange
    ) throws -> MeetingNormalizedWord {
        let range = try MeetingCanonicalSampleRange(
            startFrame: canonicalFrame(for: word.start * 16, preferPreviousBoundary: false),
            endFrame: canonicalFrame(for: word.end * 16, preferPreviousBoundary: true),
            sampleRateHertz: AssemblyAIStreamingSessionConfiguration.sampleRateHertz
        )
        guard range.startFrame >= utteranceRange.startFrame, range.endFrame <= utteranceRange.endFrame else {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
        return try MeetingNormalizedWord(
            id: deterministicUUID("word|\(utteranceID.uuidString)|\(index)|\(word.start)|\(word.end)"),
            text: word.text,
            sampleRange: range,
            confidence: word.confidence,
            speakerID: word.speaker.map(normalizedSpeakerID)
        )
    }

    private func normalizedSpeaker(_ label: String) throws -> MeetingNormalizedSpeaker {
        let id = try normalizedSpeakerID(label)
        return try MeetingNormalizedSpeaker(id: id, label: id == "UNKNOWN" ? "UNKNOWN" : "Speaker \(id)")
    }

    private func normalizedSpeakerID(_ label: String) throws -> String {
        let id = try MeetingTranscriptionValidation.normalizedIdentifier(label, field: "assemblyAI.speaker")
        guard id.utf8.count <= 32 else { throw AssemblyAIMeetingTranscriptionError.malformedResponse }
        return id
    }

    private func operation(for range: StreamRange) -> SubmittedOperation? {
        submittedOperations
            .filter { $0.streamStartFrame < range.endFrame && $0.streamEndFrame > range.startFrame }
            .max { left, right in overlap(left, range) < overlap(right, range) }
    }

    private func overlap(_ operation: SubmittedOperation, _ range: StreamRange) -> Int64 {
        max(0, min(operation.streamEndFrame, range.endFrame) - max(operation.streamStartFrame, range.startFrame))
    }

    private func canonicalFrame(for streamFrame: Int64, preferPreviousBoundary: Bool) throws -> Int64 {
        let mapping = submittedOperations.first { operation in
            if preferPreviousBoundary {
                return streamFrame > operation.streamStartFrame && streamFrame <= operation.streamEndFrame
            }
            return streamFrame >= operation.streamStartFrame && streamFrame < operation.streamEndFrame
        }
        guard let mapping else { throw AssemblyAIMeetingTranscriptionError.malformedResponse }
        return mapping.canonicalStartFrame + streamFrame - mapping.streamStartFrame
    }

    private func scheduleRotationWarning(expiresAtSeconds: Int64) {
        rotationWarningTask?.cancel()
        let expiry = expiresAtSeconds.multipliedReportingOverflow(by: 1000)
        guard !expiry.overflow else { return }
        let warningAtMilliseconds = expiry.partialValue - Int64(configuration.rotationWarningLeadSeconds * 1000)
        let delayMilliseconds = max(0, warningAtMilliseconds - nowMilliseconds())
        rotationWarningTask = Task { [weak self, sleep] in
            do {
                try await sleep(.milliseconds(delayMilliseconds))
                guard let self else { return }
                await self.emitRotationWarningIfActive()
            } catch {}
        }
    }

    private func emitRotationWarningIfActive() {
        guard state == .ready else { return }
        emitWarning(
            code: "session-rotation-required",
            message: "Rotate the AssemblyAI streaming session before its three-hour limit.",
            recoverable: true
        )
    }

    private func emitSession(_ sessionState: MeetingTranscriptionSessionState) {
        guard let eventContext = try? makeEventContext(eventID: UUID(), operationID: nil, providerEpoch: .initial),
              let event = try? MeetingTranscriptionSessionEvent(
                  context: eventContext,
                  state: sessionState,
                  providerSessionID: providerSessionID
              )
        else { return }
        eventChannel.send(.session(event))
    }

    private func emitWarning(
        code: String,
        message: String,
        recoverable: Bool,
        operationID: UUID? = nil,
        epoch: MeetingProviderEpoch = .initial
    ) {
        guard let eventContext = try? makeEventContext(eventID: UUID(), operationID: operationID, providerEpoch: epoch),
              let event = try? MeetingTranscriptionWarningEvent(
                  context: eventContext,
                  code: code,
                  message: message,
                  isRecoverable: recoverable
              )
        else { return }
        eventChannel.send(.warning(event))
    }

    private func emitFailure(code: String, classification: MeetingTranscriptionFailureClassification) {
        guard !didEmitTerminalFailure else { return }
        didEmitTerminalFailure = true
        guard let eventContext = try? makeEventContext(eventID: UUID(), operationID: nil, providerEpoch: .initial),
              let event = try? MeetingTranscriptionFailureEvent(
                  context: eventContext,
                  code: code,
                  message: "AssemblyAI streaming transcription could not continue.",
                  classification: classification
              )
        else { return }
        eventChannel.send(.failure(event))
    }

    private func makeEventContext(
        eventID: UUID,
        operationID: UUID?,
        providerEpoch: MeetingProviderEpoch
    ) throws -> MeetingTranscriptionEventContext {
        defer { sequenceNumber += 1 }
        return try MeetingTranscriptionEventContext(
            eventID: eventID,
            operationID: operationID,
            sessionID: context.sessionID,
            trackID: context.trackID,
            source: context.source,
            providerEpoch: providerEpoch,
            sequenceNumber: sequenceNumber,
            emittedAtMilliseconds: max(0, nowMilliseconds())
        )
    }

    private func deterministicUUID(_ value: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6] & 0x0F | 0x50, bytes[7],
            bytes[8] & 0x3F | 0x80, bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func finishEventStream() {
        rotationWarningTask?.cancel()
        eventChannel.finish()
    }
}
