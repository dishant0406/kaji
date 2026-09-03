import CryptoKit
import Foundation

struct DeepgramAudioMappingTable {
    struct Entry {
        let streamStartFrame: Int64
        let streamEndFrame: Int64
        let canonicalStartFrame: Int64
        let operationID: UUID
    }

    private(set) var entries: [Entry] = []

    mutating func append(_ entry: Entry) {
        entries.append(entry)
    }

    mutating func removeLast() {
        _ = entries.popLast()
    }

    mutating func prune(through streamFrame: Int64) {
        entries.removeAll { $0.streamEndFrame <= streamFrame }
    }

    func canonicalFrame(for streamFrame: Int64, preferPreviousBoundary: Bool) -> Int64? {
        guard let mapping = entries.first(where: { mapping in
            if preferPreviousBoundary {
                return streamFrame > mapping.streamStartFrame && streamFrame <= mapping.streamEndFrame
            }
            return streamFrame >= mapping.streamStartFrame && streamFrame < mapping.streamEndFrame
        })
        else {
            return nil
        }
        return mapping.canonicalStartFrame + streamFrame - mapping.streamStartFrame
    }

    func operationID(for streamFrame: Int64) -> UUID? {
        entries.first {
            streamFrame >= $0.streamStartFrame && streamFrame < $0.streamEndFrame
        }?.operationID
    }
}

enum DeepgramStreamingRequestFactory {
    static func makeRequest(
        route: MeetingTranscriptionRoute,
        context: MeetingTrackTranscriptionContextSnapshot,
        configuration: DeepgramNova3Configuration,
        endpoint: URL,
        apiKey: String
    ) throws -> URLRequest {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme == "wss",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.fragment == nil
        else {
            throw DeepgramMeetingTranscriptionError.invalidConfiguration
        }
        var queryItems = [
            URLQueryItem(name: "model", value: route.modelID),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "endpointing", value: String(configuration.endpointingMilliseconds)),
            URLQueryItem(name: "utterance_end_ms", value: String(configuration.utteranceEndMilliseconds)),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "vad_events", value: "true"),
        ]
        if route.diarizationEnabled {
            queryItems.append(URLQueryItem(name: "diarize_model", value: "latest"))
        }
        if route.languageCodes.count > 1 {
            queryItems.append(URLQueryItem(name: "language", value: "multi"))
        } else if let languageCode = route.languageCodes.first {
            queryItems.append(URLQueryItem(name: "language", value: languageCode))
        }
        queryItems.append(contentsOf: context.keyterms.map { URLQueryItem(name: "keyterm", value: $0) })
        if route.retention == .none {
            queryItems.append(URLQueryItem(name: "mip_opt_out", value: "true"))
        }
        components.queryItems = queryItems
        guard let url = components.url,
              let verified = URLComponents(url: url, resolvingAgainstBaseURL: false),
              verified.scheme == "wss",
              verified.host == components.host,
              verified.port == components.port,
              verified.path == components.path,
              verified.user == nil,
              verified.password == nil,
              verified.fragment == nil,
              url.absoluteString.utf8.count <= 16384
        else {
            throw DeepgramMeetingTranscriptionError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}

actor DeepgramMeetingTrackTranscriptionSession: MeetingTrackTranscriptionSession {
    private enum State {
        case idle
        case starting
        case started
        case draining
        case finished
        case cancelled
    }

    private struct ResultKey: Hashable {
        let providerEpoch: MeetingProviderEpoch
        let channelIndex: Int
        let streamStartFrame: Int64
    }

    private struct ResultRevision {
        let utteranceID: UUID
        let revision: Int
        let fingerprint: Data
        let isFinal: Bool
    }

    private struct FingerprintInput {
        let transcript: String
        let sampleRange: MeetingCanonicalSampleRange
        let confidence: Double
        let words: [MeetingNormalizedWord]
        let speaker: MeetingNormalizedSpeaker?
        let language: MeetingNormalizedLanguage?
    }

    nonisolated let events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>

    private let route: MeetingTranscriptionRoute
    private let context: MeetingTrackTranscriptionContextSnapshot
    private let configuration: DeepgramNova3Configuration
    private let endpoint: URL
    private let resolveAPIKey: @Sendable () throws -> String
    private let transport: any STTWebSocketTransporting
    private let nowMilliseconds: @Sendable () -> Int64
    private let keepAliveTicks: AsyncStream<Void>
    private let eventChannel: MeetingTranscriptionProviderEventChannel
    private let drainSignals: AsyncStream<Void>
    private let drainContinuation: AsyncStream<Void>.Continuation
    private var state = State.idle
    private var sequenceNumber: Int64 = 0
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var activeEpoch: MeetingProviderEpoch?
    private var providerSessionID: String?
    private var mappings = DeepgramAudioMappingTable()
    private var submittedFrameCount: Int64 = 0
    private var revisions: [ResultKey: ResultRevision] = [:]
    private var audioSinceKeepAliveTick = false
    private var lastSpeechStartedFrame: Int64?
    private var lastUtteranceEndFrame: Int64?

    init(
        route: MeetingTranscriptionRoute,
        context: MeetingTrackTranscriptionContextSnapshot,
        configuration: DeepgramNova3Configuration,
        endpoint: URL,
        resolveAPIKey: @escaping @Sendable () throws -> String,
        transport: any STTWebSocketTransporting,
        nowMilliseconds: @escaping @Sendable () -> Int64,
        keepAliveTicks: AsyncStream<Void>
    ) {
        self.route = route
        self.context = context
        self.configuration = configuration
        self.endpoint = endpoint
        self.resolveAPIKey = resolveAPIKey
        self.transport = transport
        self.nowMilliseconds = nowMilliseconds
        self.keepAliveTicks = keepAliveTicks
        let eventChannel = MeetingTranscriptionProviderEventChannel()
        self.eventChannel = eventChannel
        events = eventChannel.events
        let drainPair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        drainSignals = drainPair.stream
        drainContinuation = drainPair.continuation
    }

    func start() async throws {
        guard state == .idle else { throw DeepgramMeetingTranscriptionError.invalidState }
        state = .starting
        emitSession(.starting)
        do {
            let apiKey: String
            do {
                apiKey = try resolveAPIKey()
            } catch let error as DeepgramMeetingTranscriptionError {
                throw error
            } catch {
                throw DeepgramMeetingTranscriptionError.credentialUnavailable
            }
            let request = try DeepgramStreamingRequestFactory.makeRequest(
                route: route,
                context: context,
                configuration: configuration,
                endpoint: endpoint,
                apiKey: apiKey
            )
            let transportEvents = await transport.events()
            receiveTask = Task { [weak self] in
                for await event in transportEvents {
                    guard let self else { return }
                    await self.handleTransportEvent(event)
                }
            }
            try await transport.connect(request: request)
            try Task.checkCancellation()
            if let metadataProvider = transport as? any DeepgramWebSocketResponseMetadataProviding,
               let metadata = await metadataProvider.deepgramResponseMetadata()
            {
                try await handleResponseMetadata(metadata)
            }
            guard state == .starting else { throw DeepgramMeetingTranscriptionError.invalidState }
            state = .started
            emitSession(.ready)
            keepAliveTask = Task { [weak self, keepAliveTicks] in
                for await _ in keepAliveTicks {
                    guard let self else { return }
                    await self.keepAliveTick()
                }
            }
        } catch {
            let mapped = Self.sessionError(error)
            if state != .finished, state != .cancelled {
                emitFailure(
                    code: Self.failureCode(for: mapped),
                    classification: Self.failureClassification(for: mapped),
                    retryAfterMilliseconds: Self.retryAfterMilliseconds(from: mapped)
                )
                state = mapped == .providerRejected(.cancelled) ? .cancelled : .finished
            }
            keepAliveTask?.cancel()
            receiveTask?.cancel()
            await transport.cancel()
            eventChannel.finish()
            throw mapped
        }
    }

    func submit(_ packet: MeetingNormalizedAudioPacket) async throws {
        guard state == .started else { throw DeepgramMeetingTranscriptionError.invalidState }
        if packet.isEndOfStream {
            try await finish()
            return
        }
        guard packet.sessionID == context.sessionID,
              packet.trackID == context.trackID,
              packet.source == context.source,
              packet.sampleRateHertz == 16000,
              packet.channelCount == 1,
              packet.encoding == .pcmSigned16LittleEndian,
              packet.bytes.count == packet.sampleRange.frameCount * 2,
              packet.bytes.count <= 1024 * 1024
        else {
            throw DeepgramMeetingTranscriptionError.invalidPacket
        }
        if let activeEpoch {
            guard packet.providerEpoch == activeEpoch else {
                throw DeepgramMeetingTranscriptionError.invalidPacket
            }
        } else {
            activeEpoch = packet.providerEpoch
        }
        let mapping = DeepgramAudioMappingTable.Entry(
            streamStartFrame: submittedFrameCount,
            streamEndFrame: submittedFrameCount + packet.sampleRange.frameCount,
            canonicalStartFrame: packet.sampleRange.startFrame,
            operationID: packet.operationID
        )
        mappings.append(mapping)
        submittedFrameCount = mapping.streamEndFrame
        do {
            try await transport.send(.binary(packet.bytes))
            audioSinceKeepAliveTick = true
        } catch {
            mappings.removeLast()
            submittedFrameCount = mapping.streamStartFrame
            throw Self.sessionError(error)
        }
    }

    func finish() async throws {
        guard state == .started else {
            if state == .finished || state == .cancelled {
                return
            }
            throw DeepgramMeetingTranscriptionError.invalidState
        }
        state = .draining
        keepAliveTask?.cancel()
        emitSession(.draining)
        do {
            try await transport.send(.text("{\"type\":\"Finalize\"}"))
            try await transport.send(.text("{\"type\":\"CloseStream\"}"))
            await waitForServerDrain()
            guard state != .cancelled else { return }
            guard state == .draining else {
                throw DeepgramMeetingTranscriptionError.providerRejected(.transient)
            }
            if await transport.currentState() != .disconnected {
                try await transport.close(code: 1000, reason: nil)
            }
            state = .finished
            emitSession(.completed)
            receiveTask?.cancel()
            eventChannel.finish()
        } catch {
            let mapped = Self.sessionError(error)
            emitFailure(
                code: Self.failureCode(for: mapped),
                classification: Self.failureClassification(for: mapped),
                retryAfterMilliseconds: Self.retryAfterMilliseconds(from: mapped)
            )
            state = .finished
            receiveTask?.cancel()
            await transport.cancel()
            eventChannel.finish()
            throw mapped
        }
    }

    func cancel() async {
        guard state != .finished, state != .cancelled else { return }
        state = .cancelled
        keepAliveTask?.cancel()
        receiveTask?.cancel()
        await transport.cancel()
        emitSession(.cancelled)
        eventChannel.finish()
    }

    private func keepAliveTick() async {
        guard state == .started else { return }
        if audioSinceKeepAliveTick {
            audioSinceKeepAliveTick = false
            return
        }
        do {
            try await transport.send(.text("{\"type\":\"KeepAlive\"}"))
        } catch {
            await terminate(
                error: Self.sessionError(error),
                code: "keep-alive-failed"
            )
        }
    }

    private func handleTransportEvent(_ event: STTWebSocketEvent) async {
        switch event {
        case let .message(message):
            await handleMessage(message)
        case let .failed(error):
            guard state == .starting || state == .started else { return }
            await terminate(error: Self.sessionError(error), code: "transport-failed")
        case .closed:
            if state == .draining {
                signalDrain()
                return
            }
            guard state == .starting || state == .started else { return }
            await terminate(error: .providerRejected(.transient), code: "connection-closed")
        case .stateChanged,
             .pong:
            break
        }
    }

    private func handleMessage(_ message: STTWebSocketMessage) async {
        guard state == .starting || state == .started || state == .draining else { return }
        guard message.byteCount <= configuration.maximumEventBytes else {
            await terminate(error: .responseTooLarge, code: "provider-event-too-large")
            return
        }
        guard case let .text(text) = message else {
            await terminate(error: .protocolViolation, code: "unexpected-binary-event")
            return
        }
        do {
            switch try DeepgramStreamingEventDecoder.decode(text) {
            case let .results(result):
                try handleResult(result)
            case let .metadata(metadata):
                try handleMetadata(metadata)
            case let .speechStarted(timestamp):
                lastSpeechStartedFrame = try streamFrame(seconds: timestamp, rounding: .down)
            case let .utteranceEnd(lastWordEnd):
                if lastWordEnd >= 0 {
                    lastUtteranceEndFrame = try streamFrame(seconds: lastWordEnd, rounding: .up)
                }
            case let .warning(notice):
                emitWarning(code: Self.sanitizedCode(notice.code, fallback: "provider-warning"))
            case let .error(notice):
                let classification = Self.classify(statusCode: notice.statusCode, code: notice.code)
                if classification == .rateLimited {
                    emitRateLimit(
                        DeepgramStreamingRateLimit(
                            scope: "project-concurrency",
                            limit: nil,
                            remaining: 0,
                            resetsAtMilliseconds: nil,
                            retryAfterMilliseconds: notice.retryAfterMilliseconds
                        )
                    )
                }
                emitFailure(
                    code: Self.sanitizedCode(notice.code, fallback: "provider-error"),
                    classification: classification,
                    retryAfterMilliseconds: notice.retryAfterMilliseconds
                )
                if state == .draining {
                    signalDrain()
                }
                state = .finished
                keepAliveTask?.cancel()
                await transport.cancel()
                eventChannel.finish()
            case let .rateLimit(rateLimit):
                emitRateLimit(rateLimit)
            }
        } catch let error as DeepgramMeetingTranscriptionError {
            await terminate(error: error, code: "invalid-provider-event")
        } catch {
            await terminate(error: .protocolViolation, code: "invalid-provider-event")
        }
    }

    private func handleResult(_ result: DeepgramStreamingResult) throws {
        let transcript = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        guard result.duration > 0, result.duration <= 600 else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        guard let activeEpoch else { throw DeepgramMeetingTranscriptionError.protocolViolation }
        let resultStreamStart = try streamFrame(seconds: result.start, rounding: .down)
        let resultStreamEnd = try streamFrame(seconds: result.start + result.duration, rounding: .up)
        let minimumWordStart = try result.words.map { try streamFrame(seconds: $0.start, rounding: .down) }.min()
        let maximumWordEnd = try result.words.map { try streamFrame(seconds: $0.end, rounding: .up) }.max()
        let streamStart = min(resultStreamStart, minimumWordStart ?? resultStreamStart)
        let streamEnd = max(resultStreamEnd, maximumWordEnd ?? resultStreamEnd)
        guard streamEnd > streamStart else { throw DeepgramMeetingTranscriptionError.protocolViolation }
        let key = ResultKey(
            providerEpoch: activeEpoch,
            channelIndex: result.channelIndex,
            streamStartFrame: resultStreamStart
        )
        if revisions[key]?.isFinal == true {
            return
        }
        let canonicalStart = try canonicalFrame(for: streamStart, preferPreviousBoundary: false)
        let canonicalEnd = try canonicalFrame(for: streamEnd, preferPreviousBoundary: true)
        let sampleRange = try MeetingCanonicalSampleRange(
            startFrame: canonicalStart,
            endFrame: canonicalEnd,
            sampleRateHertz: 16000
        )
        let stableIdentity = [
            "utterance", context.sessionID.uuidString, context.trackID.uuidString,
            String(activeEpoch.rawValue), String(result.channelIndex), String(resultStreamStart),
        ].joined(separator: "|")
        let utteranceID = revisions[key]?.utteranceID ?? Self.stableUUID(stableIdentity)
        let words = try normalizedWords(result.words, utteranceID: utteranceID, utteranceRange: sampleRange)
        let speaker = try normalizedSpeaker(words: result.words)
        let languageCode = result.languages.first ?? route.languageCodes.first
        let language = try languageCode.map { try MeetingNormalizedLanguage(code: $0) }
        let fingerprint = Self.fingerprint(FingerprintInput(
            transcript: transcript,
            sampleRange: sampleRange,
            confidence: result.confidence,
            words: words,
            speaker: speaker,
            language: language
        ))
        let previous = revisions[key]
        if let previous, previous.isFinal {
            return
        }
        if let previous, previous.fingerprint == fingerprint, previous.isFinal == result.isFinal {
            return
        }
        let revision = previous.map { value in
            value.fingerprint == fingerprint ? value.revision : value.revision + 1
        } ?? 0
        let utterance = try MeetingTranscriptionUtterance(
            id: utteranceID,
            revision: revision,
            sampleRange: sampleRange,
            text: transcript,
            confidence: result.confidence,
            words: words,
            speaker: speaker,
            language: language,
            createdAtMilliseconds: max(context.startedAtMilliseconds, nowMilliseconds())
        )
        let eventContext = try makeEventContext(
            eventID: Self.stableUUID(
                "event|\(utteranceID.uuidString)|\(revision)|\(result.isFinal)|\(fingerprint.base64EncodedString())"
            ),
            operationID: operationID(for: resultStreamStart),
            providerEpoch: activeEpoch
        )
        if result.isFinal {
            eventChannel.send(.final(MeetingTranscriptionFinalEvent(context: eventContext, utterance: utterance)))
        } else if let previous {
            let replacement = try MeetingTranscriptionReplacementEvent(
                context: eventContext,
                replacesUtteranceID: utteranceID,
                replacesRevision: previous.revision,
                utterance: utterance
            )
            eventChannel.send(.replacement(replacement))
        } else {
            eventChannel.send(.partial(MeetingTranscriptionPartialEvent(context: eventContext, utterance: utterance)))
        }
        revisions[key] = ResultRevision(
            utteranceID: utteranceID,
            revision: revision,
            fingerprint: fingerprint,
            isFinal: result.isFinal
        )
        if result.speechFinal {
            lastUtteranceEndFrame = streamEnd
        }
        if result.isFinal {
            mappings.prune(through: streamEnd)
        }
    }

    private func normalizedWords(
        _ sourceWords: [DeepgramStreamingWord],
        utteranceID: UUID,
        utteranceRange: MeetingCanonicalSampleRange
    ) throws -> [MeetingNormalizedWord] {
        try sourceWords.enumerated().map { index, word in
            let startFrame = try canonicalFrame(
                for: streamFrame(seconds: word.start, rounding: .down),
                preferPreviousBoundary: false
            )
            let endFrame = try canonicalFrame(
                for: streamFrame(seconds: word.end, rounding: .up),
                preferPreviousBoundary: true
            )
            guard startFrame >= utteranceRange.startFrame,
                  endFrame <= utteranceRange.endFrame,
                  endFrame > startFrame
            else {
                throw DeepgramMeetingTranscriptionError.protocolViolation
            }
            return try MeetingNormalizedWord(
                id: Self.stableUUID("word|\(utteranceID.uuidString)|\(index)|\(startFrame)"),
                text: word.text,
                sampleRange: MeetingCanonicalSampleRange(
                    startFrame: startFrame,
                    endFrame: endFrame,
                    sampleRateHertz: 16000
                ),
                confidence: word.confidence,
                speakerID: word.speaker.map { "speaker-\($0)" },
                languageCode: word.language
            )
        }
    }

    private func normalizedSpeaker(words: [DeepgramStreamingWord]) throws -> MeetingNormalizedSpeaker? {
        let speakerWords = words.compactMap { word -> (Int, Double?)? in
            guard let speaker = word.speaker else { return nil }
            return (speaker, word.speakerConfidence)
        }
        guard !speakerWords.isEmpty else { return nil }
        let grouped = Dictionary(grouping: speakerWords, by: { $0.0 })
        guard let dominant = grouped.max(by: { left, right in
            if left.value.count != right.value.count {
                return left.value.count < right.value.count
            }
            return left.key > right.key
        })
        else { return nil }
        let confidences = dominant.value.compactMap(\.1)
        let confidence = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
        return try MeetingNormalizedSpeaker(
            id: "speaker-\(dominant.key)",
            label: "Speaker \(dominant.key + 1)",
            confidence: confidence
        )
    }

    private func handleMetadata(_ metadata: DeepgramStreamingMetadata) throws {
        providerSessionID = try MeetingTranscriptionValidation.normalizedIdentifier(
            metadata.requestID,
            field: "deepgram.requestID"
        )
        guard metadata.duration.isFinite, metadata.duration >= 0 else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        let quantity = Int64(min(metadata.duration * 1000, Double(Int64.max)).rounded())
        if state == .draining {
            signalDrain()
        }
        guard quantity > 0 else { return }
        let eventContext = try makeEventContext(eventID: UUID(), operationID: nil, providerEpoch: currentEpoch)
        let metric = try MeetingTranscriptionUsageMetric(billingUnit: "audio-millisecond", quantity: quantity)
        let usage = try MeetingTranscriptionUsageEvent(context: eventContext, metrics: [metric])
        eventChannel.send(.usage(usage))
    }

    private func handleResponseMetadata(_ metadata: DeepgramWebSocketResponseMetadata) async throws {
        if let rateLimit = Self.rateLimit(from: metadata.headers) {
            emitRateLimit(rateLimit)
        }
        guard 200 ... 299 ~= metadata.statusCode else {
            let classification = Self.classify(statusCode: metadata.statusCode, code: "http-\(metadata.statusCode)")
            let retry = Self.retryAfterMilliseconds(headers: metadata.headers)
            emitFailure(
                code: "http-\(metadata.statusCode)",
                classification: classification,
                retryAfterMilliseconds: retry
            )
            await transport.cancel()
            state = .finished
            eventChannel.finish()
            throw DeepgramMeetingTranscriptionError.providerRejected(classification)
        }
    }

    private func terminate(error: DeepgramMeetingTranscriptionError, code: String) async {
        guard state != .finished, state != .cancelled else { return }
        if state == .draining {
            signalDrain()
        }
        emitFailure(
            code: code,
            classification: Self.failureClassification(for: error),
            retryAfterMilliseconds: Self.retryAfterMilliseconds(from: error)
        )
        state = .finished
        keepAliveTask?.cancel()
        await transport.cancel()
        eventChannel.finish()
    }

    private func waitForServerDrain() async {
        let signals = drainSignals
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                var iterator = signals.makeAsyncIterator()
                _ = await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func signalDrain() {
        switch drainContinuation.yield() {
        case .enqueued,
             .dropped:
            break
        case .terminated:
            drainContinuation.finish()
        @unknown default:
            drainContinuation.finish()
        }
    }

    private func emitSession(_ sessionState: MeetingTranscriptionSessionState) {
        guard let eventContext = try? makeEventContext(
            eventID: UUID(),
            operationID: nil,
            providerEpoch: currentEpoch
        ), let event = try? MeetingTranscriptionSessionEvent(
            context: eventContext,
            state: sessionState,
            providerSessionID: providerSessionID
        )
        else { return }
        eventChannel.send(.session(event))
    }

    private func emitWarning(code: String) {
        guard let eventContext = try? makeEventContext(
            eventID: UUID(),
            operationID: nil,
            providerEpoch: currentEpoch
        ), let event = try? MeetingTranscriptionWarningEvent(
            context: eventContext,
            code: code,
            message: "Deepgram reported a recoverable warning.",
            isRecoverable: true
        )
        else { return }
        eventChannel.send(.warning(event))
    }

    private func emitFailure(
        code: String,
        classification: MeetingTranscriptionFailureClassification,
        retryAfterMilliseconds: Int64? = nil
    ) {
        guard let eventContext = try? makeEventContext(
            eventID: UUID(),
            operationID: nil,
            providerEpoch: currentEpoch
        ), let event = try? MeetingTranscriptionFailureEvent(
            context: eventContext,
            code: Self.sanitizedCode(code, fallback: "deepgram-failure"),
            message: Self.failureMessage(classification),
            classification: classification,
            retryAfterMilliseconds: retryAfterMilliseconds
        )
        else { return }
        eventChannel.send(.failure(event))
    }

    private func emitRateLimit(_ rateLimit: DeepgramStreamingRateLimit) {
        guard let eventContext = try? makeEventContext(
            eventID: UUID(),
            operationID: nil,
            providerEpoch: currentEpoch
        ), let event = try? MeetingTranscriptionRateLimitEvent(
            context: eventContext,
            scope: Self.sanitizedCode(rateLimit.scope, fallback: "project-concurrency"),
            limit: rateLimit.limit,
            remaining: rateLimit.remaining,
            resetsAtMilliseconds: rateLimit.resetsAtMilliseconds,
            retryAfterMilliseconds: rateLimit.retryAfterMilliseconds
        )
        else { return }
        eventChannel.send(.rateLimit(event))
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

    private var currentEpoch: MeetingProviderEpoch {
        activeEpoch ?? .initial
    }

    private func streamFrame(
        seconds: Double,
        rounding: FloatingPointRoundingRule
    ) throws -> Int64 {
        guard seconds.isFinite, seconds >= 0 else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        let frames = seconds * 16000
        guard frames.isFinite, frames <= Double(Int64.max) else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return Int64(frames.rounded(rounding))
    }

    private func canonicalFrame(for streamFrame: Int64, preferPreviousBoundary: Bool) throws -> Int64 {
        guard let frame = mappings.canonicalFrame(
            for: streamFrame,
            preferPreviousBoundary: preferPreviousBoundary
        )
        else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return frame
    }

    private func operationID(for streamFrame: Int64) -> UUID? {
        mappings.operationID(for: streamFrame)
    }

    private static func fingerprint(_ input: FingerprintInput) -> Data {
        var value = "\(input.transcript)|\(input.sampleRange.startFrame)|\(input.sampleRange.endFrame)|\(input.confidence)"
        for word in input.words {
            value += "|\(word.id.uuidString)|\(word.text)|\(word.sampleRange?.startFrame ?? -1)|\(word.sampleRange?.endFrame ?? -1)"
            value += "|\(word.confidence ?? -1)|\(word.speakerID ?? "")|\(word.languageCode ?? "")"
        }
        value += "|\(input.speaker?.id ?? "")|\(input.language?.code ?? "")"
        return Data(SHA256.hash(data: Data(value.utf8)))
    }

    private static func stableUUID(_ value: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func sanitizedCode(_ value: String, fallback: String) -> String {
        let lowercase = value.lowercased()
        var result = ""
        var lastWasSeparator = false
        for scalar in lowercase.unicodeScalars {
            let allowed = CharacterSet.alphanumerics.contains(scalar)
            if allowed {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator, !result.isEmpty {
                result.append("-")
                lastWasSeparator = true
            }
            if result.utf8.count >= 96 {
                break
            }
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? fallback : result
    }

    private static func classify(
        statusCode: Int?,
        code: String
    ) -> MeetingTranscriptionFailureClassification {
        let normalizedCode = sanitizedCode(code, fallback: "provider-error")
        if normalizedCode.contains("insufficient-permissions") {
            return .authorization
        }
        if normalizedCode.contains("invalid-auth") || normalizedCode.contains("unauthorized") {
            return .authentication
        }
        if normalizedCode.contains("too-many-requests") || normalizedCode.contains("rate-limit") {
            return .rateLimited
        }
        if normalizedCode.contains("payment-required") || normalizedCode.contains("quota") {
            return .quotaExceeded
        }
        if normalizedCode.hasPrefix("net-") {
            return .transient
        }
        if normalizedCode.hasPrefix("data-") {
            return .invalidRequest
        }
        guard let statusCode else { return .permanent }
        switch statusCode {
        case 401: return .authentication
        case 403: return .authorization
        case 402: return .quotaExceeded
        case 408: return .transient
        case 429: return .rateLimited
        case 499: return .cancelled
        case 500 ... 599: return .unavailable
        case 400 ... 498: return .invalidRequest
        default: return .permanent
        }
    }

    private static func sessionError(_ error: Error) -> DeepgramMeetingTranscriptionError {
        if let error = error as? DeepgramMeetingTranscriptionError {
            return error
        }
        if error is CancellationError {
            return .providerRejected(.cancelled)
        }
        if let error = error as? STTNetworkError {
            switch error {
            case .cancelled:
                return .providerRejected(.cancelled)
            case .timedOut,
                 .connectionFailed:
                return .providerRejected(.transient)
            case .invalidConfiguration,
                 .invalidResponse,
                 .protocolViolation:
                return .protocolViolation
            case .responseTooLarge:
                return .responseTooLarge
            }
        }
        return .providerRejected(.transient)
    }

    private static func failureClassification(
        for error: DeepgramMeetingTranscriptionError
    ) -> MeetingTranscriptionFailureClassification {
        switch error {
        case let .providerRejected(classification): classification
        case .credentialUnavailable,
             .invalidCredential: .authentication
        case .invalidConfiguration,
             .invalidRoute,
             .invalidPacket,
             .invalidState: .invalidRequest
        case .responseTooLarge,
             .protocolViolation: .permanent
        }
    }

    private static func failureCode(for error: DeepgramMeetingTranscriptionError) -> String {
        switch error {
        case .credentialUnavailable: "credential-unavailable"
        case .invalidCredential: "invalid-credential"
        case .invalidConfiguration: "invalid-configuration"
        case .invalidRoute: "invalid-route"
        case .invalidPacket: "invalid-packet"
        case .invalidState: "invalid-state"
        case .responseTooLarge: "provider-event-too-large"
        case .protocolViolation: "provider-protocol-violation"
        case let .providerRejected(classification): "provider-\(classification.rawValue)"
        }
    }

    private static func failureMessage(_ classification: MeetingTranscriptionFailureClassification) -> String {
        switch classification {
        case .authentication: "Deepgram authentication failed."
        case .authorization: "Deepgram denied access to the requested transcription service."
        case .rateLimited: "Deepgram concurrency is currently limited."
        case .quotaExceeded: "The Deepgram project has insufficient transcription quota."
        case .cancelled: "Deepgram transcription was cancelled."
        case .invalidRequest: "Deepgram rejected the transcription request."
        case .unavailable,
             .transient: "Deepgram transcription is temporarily unavailable."
        case .permanent: "Deepgram transcription could not continue."
        }
    }

    private static func retryAfterMilliseconds(from error: DeepgramMeetingTranscriptionError) -> Int64? {
        if case .providerRejected(.rateLimited) = error {
            return nil
        }
        return nil
    }

    private static func rateLimit(from headers: [String: String]) -> DeepgramStreamingRateLimit? {
        let limit = headers["x-ratelimit-limit"].flatMap(Int64.init)
        let remaining = headers["x-ratelimit-remaining"].flatMap(Int64.init)
        let reset = headers["x-ratelimit-reset"].flatMap(Int64.init)
        let retry = retryAfterMilliseconds(headers: headers)
        guard limit != nil || remaining != nil || reset != nil || retry != nil else { return nil }
        return DeepgramStreamingRateLimit(
            scope: headers["x-ratelimit-scope"] ?? "project-concurrency",
            limit: limit,
            remaining: remaining,
            resetsAtMilliseconds: reset,
            retryAfterMilliseconds: retry
        )
    }

    private static func retryAfterMilliseconds(headers: [String: String]) -> Int64? {
        guard let delay = STTRetryAfterParser.delay(from: headers["retry-after"]) else { return nil }
        return Int64(min(delay * 1000, 3_600_000).rounded(.up))
    }
}
