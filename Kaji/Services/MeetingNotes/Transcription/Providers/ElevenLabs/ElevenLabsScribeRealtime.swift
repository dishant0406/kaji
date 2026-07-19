import Foundation

actor ElevenLabsScribeRealtimeSession: MeetingTrackTranscriptionSession {
    private enum State {
        case idle
        case starting
        case started
        case draining
        case finished
        case cancelled
        case failed
    }

    private struct Segment {
        let id: UUID
        let operationID: UUID?
        let sampleRange: MeetingCanonicalSampleRange
        let epoch: MeetingProviderEpoch
        var revision: Int
    }

    nonisolated let events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>

    private let route: MeetingTranscriptionRoute
    private let context: MeetingTrackTranscriptionContextSnapshot
    private let credentialResolver: any ElevenLabsScribeCredentialResolving
    private let transport: any STTWebSocketTransporting
    private let options: ElevenLabsScribeRealtimeOptions
    private let nowMilliseconds: @Sendable () -> Int64
    private let eventChannel: MeetingTranscriptionProviderEventChannel
    private var state = State.idle
    private var eventLoopTask: Task<Void, Never>?
    private var sequenceNumber: Int64 = 0
    private var providerSessionID: String?
    private let endpoint: URL
    private var segmentIndex: UInt64 = 0
    private var activeSegmentID: UUID?
    private var activeOperationID: UUID?
    private var activeStartFrame: Int64?
    private var activeEndFrame: Int64?
    private var activeEpoch = MeetingProviderEpoch.initial
    private var activeRevision = -1
    private var activeAudioFrameCount: Int64 = 0
    private var pendingSegments: [UUID: Segment] = [:]
    private var pendingSegmentOrder: [UUID] = []
    private var pendingCommittedTexts: [UUID: String] = [:]
    private var totalFrameCount: Int64 = 0
    private var lastPacketEndFrame: Int64?

    init(
        route: MeetingTranscriptionRoute,
        context: MeetingTrackTranscriptionContextSnapshot,
        credentialResolver: any ElevenLabsScribeCredentialResolving,
        transport: any STTWebSocketTransporting,
        options: ElevenLabsScribeRealtimeOptions,
        endpoint: URL,
        nowMilliseconds: @escaping @Sendable () -> Int64
    ) {
        self.route = route
        self.context = context
        self.credentialResolver = credentialResolver
        self.transport = transport
        self.options = options
        self.endpoint = endpoint
        self.nowMilliseconds = nowMilliseconds
        let eventChannel = MeetingTranscriptionProviderEventChannel()
        self.eventChannel = eventChannel
        events = eventChannel.events
    }

    func start() async throws {
        guard state == .idle else { throw ElevenLabsScribeError.invalidState }
        state = .starting
        try emitSession(.starting)
        let apiKey = try await ElevenLabsScribeMeetingTranscriptionProvider.validAPIKey(from: credentialResolver)
        var request = try URLRequest(url: webSocketURL())
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let stream = await transport.events()
        eventLoopTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { return }
                await self?.handle(event)
            }
        }
        do {
            try await transport.connect(request: request)
            try await waitForStart()
        } catch let error as ElevenLabsScribeError {
            await fail(error)
            throw error
        } catch {
            let wrapped = Self.networkError(error)
            await fail(wrapped)
            throw wrapped
        }
    }

    func submit(_ packet: MeetingNormalizedAudioPacket) async throws {
        guard state == .started else { throw ElevenLabsScribeError.invalidState }
        if packet.isEndOfStream {
            try await finish()
            return
        }
        try validate(packet)
        let pcm16 = try ElevenLabsScribePCM16.packetData(packet)
        let frameCount = packet.sampleRange.frameCount
        guard totalFrameCount + frameCount <= Int64(options.maximumSessionSeconds * 16000) else {
            throw ElevenLabsScribeError.requestTooLarge
        }
        totalFrameCount += frameCount
        lastPacketEndFrame = packet.sampleRange.endFrame
        let maximumFrames = options.maximumFrameDurationMilliseconds * 16
        let manualCommitFrames = Int64(options.manualCommitWindowSeconds * 16000)
        var frameOffset: Int64 = 0
        while frameOffset < frameCount {
            var chunkFrames = min(Int64(maximumFrames), frameCount - frameOffset)
            if options.commitStrategy == .manual {
                chunkFrames = min(chunkFrames, manualCommitFrames - activeAudioFrameCount)
            }
            let chunkStartFrame = packet.sampleRange.startFrame + frameOffset
            let chunkEndFrame = chunkStartFrame + chunkFrames
            extendActiveSegment(
                packet: packet,
                startFrame: chunkStartFrame,
                endFrame: chunkEndFrame,
                frameCount: chunkFrames
            )
            let shouldCommit = options.commitStrategy == .manual && activeAudioFrameCount == manualCommitFrames
            let committedSegment = shouldCommit ? try currentSegment() : nil
            if let committedSegment {
                do {
                    try enqueuePending(committedSegment)
                } catch let error as ElevenLabsScribeError {
                    await fail(error)
                    throw error
                }
            }
            let byteOffset = Int(frameOffset) * 2
            let byteEnd = byteOffset + Int(chunkFrames) * 2
            let message = try audioMessage(
                bytes: pcm16.subdata(in: byteOffset ..< byteEnd),
                commit: shouldCommit
            )
            do {
                try await transport.send(.text(message))
            } catch {
                if let committedSegment { removePending(id: committedSegment.id) }
                let wrapped = Self.networkError(error)
                await fail(wrapped)
                throw wrapped
            }
            if shouldCommit { resetActiveSegment() }
            frameOffset += chunkFrames
        }
    }

    func finish() async throws {
        guard state == .started else {
            if state == .finished || state == .cancelled { return }
            throw ElevenLabsScribeError.invalidState
        }
        state = .draining
        try emitSession(.draining)
        do {
            if activeStartFrame != nil {
                let segment = try currentSegment()
                try enqueuePending(segment)
                do {
                    try await transport.send(.text(audioMessage(bytes: Data(), commit: true)))
                    resetActiveSegment()
                } catch {
                    removePending(id: segment.id)
                    throw error
                }
            }
            try await waitForPendingSegments()
            try await transport.close(code: 1000, reason: nil)
        } catch {
            let wrapped = Self.networkError(error)
            await fail(wrapped)
            throw wrapped
        }
        state = .finished
        try emitSession(.completed)
        eventLoopTask?.cancel()
        eventChannel.finish()
    }

    func cancel() async {
        guard state != .finished, state != .cancelled else { return }
        state = .cancelled
        eventLoopTask?.cancel()
        await transport.cancel()
        try? emitSession(.cancelled)
        eventChannel.finish()
    }

    private func webSocketURL() throws -> URL {
        guard route.retention == .providerDefault || route.retention == .none || route.retention == .configurable,
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme == "wss",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.fragment == nil
        else {
            throw ElevenLabsScribeError.invalidRoute
        }
        var queryItems = [
            URLQueryItem(name: "model_id", value: route.modelID),
            URLQueryItem(name: "include_timestamps", value: "true"),
            URLQueryItem(name: "include_language_detection", value: String(options.includeLanguageDetection)),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "commit_strategy", value: options.commitStrategy.rawValue),
            URLQueryItem(name: "no_verbatim", value: String(options.noVerbatim)),
            URLQueryItem(name: "vad_silence_threshold_secs", value: Self.decimal(options.vadSilenceThresholdSeconds)),
            URLQueryItem(name: "vad_threshold", value: Self.decimal(options.vadThreshold)),
            URLQueryItem(name: "min_speech_duration_ms", value: String(options.minimumSpeechDurationMilliseconds)),
            URLQueryItem(name: "min_silence_duration_ms", value: String(options.minimumSilenceDurationMilliseconds)),
            URLQueryItem(name: "enable_logging", value: route.retention == .none ? "false" : "true"),
        ]
        if let languageCode = route.languageCodes.first {
            queryItems.append(URLQueryItem(name: "language_code", value: languageCode))
        }
        queryItems.append(contentsOf: context.keyterms.map { URLQueryItem(name: "keyterms", value: $0) })
        components.queryItems = queryItems
        guard let url = components.url else { throw ElevenLabsScribeError.invalidConfiguration("realtime-url") }
        return url
    }

    private func validate(_ packet: MeetingNormalizedAudioPacket) throws {
        guard packet.sessionID == context.sessionID,
              packet.trackID == context.trackID,
              packet.source == context.source,
              packet.sampleRateHertz == 16000,
              packet.channelCount == 1,
              packet.sampleRange.frameCount > 0,
              lastPacketEndFrame.map({ packet.sampleRange.startFrame >= $0 }) ?? true
        else {
            throw ElevenLabsScribeError.invalidPacket
        }
    }

    private func extendActiveSegment(
        packet: MeetingNormalizedAudioPacket,
        startFrame: Int64,
        endFrame: Int64,
        frameCount: Int64
    ) {
        if activeSegmentID == nil {
            activeSegmentID = ElevenLabsScribeIdentity.derivedUUID(namespace: context.trackID, index: segmentIndex)
            activeOperationID = packet.operationID
            activeStartFrame = startFrame
            activeRevision = -1
        }
        activeEndFrame = max(activeEndFrame ?? endFrame, endFrame)
        activeAudioFrameCount += frameCount
        activeEpoch = packet.providerEpoch
    }

    private func currentSegment() throws -> Segment {
        guard let id = activeSegmentID,
              let startFrame = activeStartFrame,
              let endFrame = activeEndFrame,
              endFrame > startFrame
        else {
            throw ElevenLabsScribeError.invalidState
        }
        return try Segment(
            id: id,
            operationID: activeOperationID,
            sampleRange: MeetingCanonicalSampleRange(
                startFrame: startFrame,
                endFrame: endFrame,
                sampleRateHertz: 16000
            ),
            epoch: activeEpoch,
            revision: activeRevision
        )
    }

    private func audioMessage(bytes: Data, commit: Bool) throws -> String {
        guard bytes.count.isMultiple(of: 2),
              bytes.count <= options.maximumFrameDurationMilliseconds * 32,
              !bytes.isEmpty || commit
        else {
            throw ElevenLabsScribeError.invalidPacket
        }
        let object: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": bytes.base64EncodedString(),
            "commit": commit,
            "sample_rate": 16000,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= 64 * 1024,
              let value = String(data: data, encoding: .utf8)
        else {
            throw ElevenLabsScribeError.requestTooLarge
        }
        return value
    }

    private func handle(_ event: STTWebSocketEvent) async {
        guard state != .finished, state != .cancelled, state != .failed else { return }
        do {
            switch event {
            case let .message(message):
                guard case let .text(value) = message,
                      value.utf8.count <= 1024 * 1024,
                      let data = value.data(using: .utf8)
                else {
                    throw ElevenLabsScribeError.malformedResponse
                }
                try handleMessage(data)
            case let .failed(networkError):
                throw Self.networkError(networkError)
            case let .closed(code):
                if state != .draining, code != 1000 {
                    throw ElevenLabsScribeError.providerFailure(
                        code: "websocket-closed",
                        classification: .transient,
                        retryAfterMilliseconds: nil
                    )
                }
            case .stateChanged,
                 .pong:
                break
            }
        } catch let error as ElevenLabsScribeError {
            await fail(error)
        } catch {
            await fail(.malformedResponse)
        }
    }

    private func handleMessage(_ data: Data) throws {
        let object = try Self.dictionary(data)
        guard let messageType = object["message_type"] as? String else {
            throw ElevenLabsScribeError.malformedResponse
        }
        switch messageType {
        case "session_started":
            try handleSessionStarted(object)
        case "partial_transcript":
            try handlePartial(object)
        case "committed_transcript":
            try handleCommitted(object)
        case "committed_transcript_with_timestamps":
            try handleTimestampedCommit(object)
        case "auth_error":
            throw Self.eventError(object, classification: .authentication)
        case "quota_exceeded":
            throw Self.eventError(object, classification: .quotaExceeded)
        case "rate_limited",
             "commit_throttled":
            throw Self.eventError(object, classification: .rateLimited)
        case "queue_overflow",
             "resource_exhausted",
             "transcriber_error",
             "error":
            throw Self.eventError(object, classification: .transient)
        case "input_error",
             "chunk_size_exceeded",
             "unaccepted_terms":
            throw Self.eventError(object, classification: .invalidRequest)
        case "session_time_limit_exceeded",
             "insufficient_audio_activity":
            throw Self.eventError(object, classification: .unavailable)
        default:
            throw ElevenLabsScribeError.malformedResponse
        }
    }

    private func handleSessionStarted(_ object: [String: Any]) throws {
        guard state == .starting,
              Set(object.keys) == ["message_type", "session_id", "config"],
              let sessionID = object["session_id"] as? String,
              ElevenLabsScribeBatchResponseParser.isSafeProviderIdentifier(sessionID),
              let config = object["config"] as? [String: Any]
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        try validateSessionConfig(config)
        providerSessionID = sessionID
        state = .started
        try emitSession(.ready, providerSessionID: sessionID)
    }

    private func validateSessionConfig(_ config: [String: Any]) throws {
        let allowed = Set([
            "sample_rate", "audio_format", "language_code", "commit_strategy", "vad_silence_threshold_secs",
            "vad_threshold", "min_speech_duration_ms", "min_silence_duration_ms", "model_id", "enable_logging",
            "include_timestamps", "include_language_detection", "keyterms", "no_verbatim",
        ])
        guard Set(config.keys).isSubset(of: allowed),
              Self.integer(config["sample_rate"]) == 16000,
              config["audio_format"] as? String == "pcm_16000",
              config["model_id"] as? String == route.modelID,
              config["commit_strategy"] as? String == options.commitStrategy.rawValue,
              config["enable_logging"] as? Bool == (route.retention != .none),
              config["include_timestamps"] as? Bool == true,
              config["include_language_detection"] as? Bool == options.includeLanguageDetection,
              config["no_verbatim"] as? Bool == options.noVerbatim,
              Self.finiteDouble(config["vad_silence_threshold_secs"]) == options.vadSilenceThresholdSeconds,
              Self.finiteDouble(config["vad_threshold"]) == options.vadThreshold,
              Self.integer(config["min_speech_duration_ms"]) == options.minimumSpeechDurationMilliseconds,
              Self.integer(config["min_silence_duration_ms"]) == options.minimumSilenceDurationMilliseconds,
              Self.optionalString(config["language_code"]) == route.languageCodes.first,
              Self.optionalStrings(config["keyterms"]) == context.keyterms
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
    }

    private func handlePartial(_ object: [String: Any]) throws {
        guard Set(object.keys) == ["message_type", "text"],
              let text = Self.normalizedText(object["text"], maximumCharacters: 100_000)
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        let segmentID: UUID
        let sampleRange: MeetingCanonicalSampleRange
        let operationID: UUID?
        let epoch: MeetingProviderEpoch
        let previousRevision: Int
        let revision: Int
        if let activeSegmentID, let activeSegment = try? currentSegment() {
            segmentID = activeSegmentID
            sampleRange = activeSegment.sampleRange
            operationID = activeOperationID
            epoch = activeEpoch
            previousRevision = activeRevision
            activeRevision += 1
            revision = activeRevision
        } else if let pendingID = pendingSegmentOrder.last, var pending = pendingSegments[pendingID] {
            segmentID = pendingID
            sampleRange = pending.sampleRange
            operationID = pending.operationID
            epoch = pending.epoch
            previousRevision = pending.revision
            pending.revision += 1
            revision = pending.revision
            pendingSegments[pendingID] = pending
        } else {
            throw ElevenLabsScribeError.malformedResponse
        }
        let utterance = try MeetingTranscriptionUtterance(
            id: segmentID,
            revision: revision,
            sampleRange: sampleRange,
            text: text,
            language: route.languageCodes.first.map { try MeetingNormalizedLanguage(code: $0) },
            createdAtMilliseconds: max(context.startedAtMilliseconds, nowMilliseconds())
        )
        let eventContext = try eventContext(
            eventID: ElevenLabsScribeIdentity.derivedUUID(namespace: segmentID, index: UInt64(revision + 1)),
            operationID: operationID,
            epoch: epoch,
            emittedAtMilliseconds: nowMilliseconds()
        )
        if previousRevision < 0 {
            eventChannel.send(.partial(MeetingTranscriptionPartialEvent(
                context: eventContext,
                utterance: utterance
            )))
        } else {
            try eventChannel.send(.replacement(MeetingTranscriptionReplacementEvent(
                context: eventContext,
                replacesUtteranceID: segmentID,
                replacesRevision: previousRevision,
                utterance: utterance
            )))
        }
    }

    private func handleCommitted(_ object: [String: Any]) throws {
        guard Set(object.keys) == ["message_type", "text"],
              let text = Self.normalizedCommittedText(object["text"], maximumCharacters: 100_000)
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        if nextPendingIDAwaitingText() == nil {
            let segment = try currentSegment()
            try enqueuePending(segment)
            resetActiveSegment()
        }
        guard let segmentID = nextPendingIDAwaitingText() else {
            throw ElevenLabsScribeError.malformedResponse
        }
        pendingCommittedTexts[segmentID] = text
    }

    private func handleTimestampedCommit(_ object: [String: Any]) throws {
        guard Set(object.keys).isSubset(of: ["message_type", "text", "language_code", "words"]),
              let text = Self.normalizedCommittedText(object["text"], maximumCharacters: 100_000),
              let segmentID = pendingSegmentOrder.first,
              let segment = pendingSegments[segmentID],
              text == pendingCommittedTexts[segmentID]
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        let rawWords: [Any]
        if object["words"] == nil || object["words"] is NSNull {
            rawWords = []
        } else if let values = object["words"] as? [Any], values.count <= 10000 {
            rawWords = values
        } else {
            throw ElevenLabsScribeError.malformedResponse
        }
        removePending(id: segmentID)
        guard !text.isEmpty else { return }
        let languageCode = try Self.languageCode(object["language_code"], fallback: route.languageCodes.first)
        let words = try rawWords.enumerated().compactMap { index, raw in
            try normalizedWord(raw, index: index, segment: segment, languageCode: languageCode)
        }
        let confidenceValues = words.compactMap(\.confidence)
        let confidence = confidenceValues.isEmpty ? nil : confidenceValues.reduce(0, +) / Double(confidenceValues.count)
        let finalRevision = max(0, segment.revision + 1)
        let utterance = try MeetingTranscriptionUtterance(
            id: segment.id,
            revision: finalRevision,
            sampleRange: segment.sampleRange,
            text: text,
            confidence: confidence,
            words: words,
            language: languageCode.map { try MeetingNormalizedLanguage(code: $0) },
            createdAtMilliseconds: max(context.startedAtMilliseconds, nowMilliseconds())
        )
        try eventChannel.send(.final(MeetingTranscriptionFinalEvent(
            context: eventContext(
                eventID: ElevenLabsScribeIdentity.derivedUUID(namespace: segment.id, index: UInt64.max),
                operationID: segment.operationID,
                epoch: segment.epoch,
                emittedAtMilliseconds: nowMilliseconds()
            ),
            utterance: utterance
        )))
    }

    private func normalizedWord(
        _ raw: Any,
        index: Int,
        segment: Segment,
        languageCode: String?
    ) throws -> MeetingNormalizedWord? {
        guard let object = raw as? [String: Any],
              Set(object.keys).isSubset(of: ["text", "start", "end", "type", "speaker_id", "logprob", "characters"]),
              Self.absentOrNull(object["characters"]),
              let text = object["text"] as? String,
              !text.isEmpty,
              text.count <= 1000,
              let type = object["type"] as? String,
              type == "word" || type == "spacing",
              let start = Self.finiteDouble(object["start"]),
              let end = Self.finiteDouble(object["end"]),
              start >= 0,
              end > start,
              let logProbability = Self.finiteDouble(object["logprob"]),
              logProbability <= 0
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        guard type == "word" else { return nil }
        let startFrame = segment.sampleRange.startFrame + Int64((start * 16000).rounded())
        let endFrame = segment.sampleRange.startFrame + Int64((end * 16000).rounded())
        guard startFrame >= segment.sampleRange.startFrame,
              endFrame <= segment.sampleRange.endFrame,
              endFrame > startFrame
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        return try MeetingNormalizedWord(
            id: ElevenLabsScribeIdentity.derivedUUID(namespace: segment.id, index: UInt64(index + 1)),
            text: text,
            sampleRange: MeetingCanonicalSampleRange(
                startFrame: startFrame,
                endFrame: endFrame,
                sampleRateHertz: 16000
            ),
            confidence: exp(logProbability),
            speakerID: nil,
            languageCode: languageCode
        )
    }

    private func waitForStart() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(options.startTimeoutSeconds))
        while state == .starting, clock.now < deadline {
            try Task.checkCancellation()
            try await clock.sleep(for: .milliseconds(10))
        }
        guard state == .started else {
            if state == .failed { throw ElevenLabsScribeError.providerFailure(
                code: "session-start-failed",
                classification: .unavailable,
                retryAfterMilliseconds: nil
            ) }
            throw ElevenLabsScribeError.providerFailure(
                code: "session-start-timeout",
                classification: .transient,
                retryAfterMilliseconds: nil
            )
        }
    }

    private func waitForPendingSegments() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(options.finishTimeoutSeconds))
        while !pendingSegmentOrder.isEmpty, clock.now < deadline {
            guard state == .started || state == .draining else {
                throw ElevenLabsScribeError.providerFailure(
                    code: "realtime-session-failed",
                    classification: .unavailable,
                    retryAfterMilliseconds: nil
                )
            }
            try Task.checkCancellation()
            try await clock.sleep(for: .milliseconds(10))
        }
        guard pendingSegmentOrder.isEmpty else {
            throw ElevenLabsScribeError.providerFailure(
                code: "commit-timeout",
                classification: .transient,
                retryAfterMilliseconds: nil
            )
        }
    }

    private func resetActiveSegment() {
        segmentIndex += 1
        activeSegmentID = nil
        activeOperationID = nil
        activeStartFrame = nil
        activeEndFrame = nil
        activeRevision = -1
        activeAudioFrameCount = 0
    }

    private func enqueuePending(_ segment: Segment) throws {
        guard pendingSegments.count < 8, pendingSegments[segment.id] == nil else {
            throw ElevenLabsScribeError.providerFailure(
                code: "commit-backlog-full",
                classification: .transient,
                retryAfterMilliseconds: nil
            )
        }
        pendingSegments[segment.id] = segment
        pendingSegmentOrder.append(segment.id)
    }

    private func removePending(id: UUID) {
        pendingSegments[id] = nil
        pendingCommittedTexts[id] = nil
        pendingSegmentOrder.removeAll { $0 == id }
    }

    private func nextPendingIDAwaitingText() -> UUID? {
        pendingSegmentOrder.first { pendingCommittedTexts[$0] == nil }
    }

    private func emitSession(
        _ sessionState: MeetingTranscriptionSessionState,
        providerSessionID: String? = nil
    ) throws {
        try eventChannel.send(.session(MeetingTranscriptionSessionEvent(
            context: eventContext(
                eventID: UUID(),
                operationID: nil,
                epoch: .initial,
                emittedAtMilliseconds: nowMilliseconds()
            ),
            state: sessionState,
            providerSessionID: providerSessionID
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

    private func fail(_ error: ElevenLabsScribeError) async {
        guard state != .failed, state != .finished, state != .cancelled else { return }
        state = .failed
        if error.failureClassification == .rateLimited,
           let eventContext = try? eventContext(
               eventID: UUID(),
               operationID: activeOperationID,
               epoch: activeEpoch,
               emittedAtMilliseconds: nowMilliseconds()
           ),
           let event = try? MeetingTranscriptionRateLimitEvent(
               context: eventContext,
               scope: "elevenlabs-scribe-realtime",
               retryAfterMilliseconds: error.retryAfterMilliseconds
           )
        {
            eventChannel.send(.rateLimit(event))
        }
        if let eventContext = try? eventContext(
            eventID: UUID(),
            operationID: activeOperationID,
            epoch: activeEpoch,
            emittedAtMilliseconds: nowMilliseconds()
        ), let event = try? MeetingTranscriptionFailureEvent(
            context: eventContext,
            code: error.code,
            message: error.safeMessage,
            classification: error.failureClassification,
            retryAfterMilliseconds: error.retryAfterMilliseconds
        ) {
            eventChannel.send(.failure(event))
        }
        await transport.cancel()
        eventLoopTask?.cancel()
        eventChannel.finish()
    }

    private static func eventError(
        _ object: [String: Any],
        classification: MeetingTranscriptionFailureClassification
    ) -> ElevenLabsScribeError {
        let type = object["message_type"] as? String ?? "error"
        let allowed = Set(["message_type", "error"])
        guard Set(object.keys).isSubset(of: allowed),
              object["error"] is String,
              let code = normalizedErrorCode(type)
        else {
            return .malformedResponse
        }
        return .providerFailure(code: code, classification: classification, retryAfterMilliseconds: nil)
    }

    private static func normalizedErrorCode(_ value: String) -> String? {
        let normalized = value.replacingOccurrences(of: "_", with: "-")
        return ElevenLabsScribeBatchResponseParser.isSafeProviderIdentifier(normalized) ? normalized : nil
    }

    private static func networkError(_ error: Error) -> ElevenLabsScribeError {
        if let error = error as? ElevenLabsScribeError { return error }
        if error is CancellationError {
            return .providerFailure(code: "cancelled", classification: .cancelled, retryAfterMilliseconds: nil)
        }
        if let error = error as? STTNetworkError {
            let classification: MeetingTranscriptionFailureClassification = switch error {
            case .cancelled: .cancelled
            case .timedOut,
                 .connectionFailed:
                .transient
            case .invalidConfiguration,
                 .protocolViolation:
                .invalidRequest
            case .invalidResponse,
                 .responseTooLarge:
                .permanent
            }
            return .providerFailure(
                code: "websocket-transport-failure",
                classification: classification,
                retryAfterMilliseconds: nil
            )
        }
        return .providerFailure(
            code: "websocket-transport-failure",
            classification: .transient,
            retryAfterMilliseconds: nil
        )
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty,
              data.count <= 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.count <= 32
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        return object
    }

    private static func normalizedText(_ value: Any?, maximumCharacters: Int) -> String? {
        guard let value = value as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.count <= maximumCharacters,
              !normalized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" })
        else {
            return nil
        }
        return normalized
    }

    private static func normalizedCommittedText(_ value: Any?, maximumCharacters: Int) -> String? {
        guard let value = value as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= maximumCharacters,
              !normalized.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) && $0 != "\n"
              })
        else {
            return nil
        }
        return normalized
    }

    private static func languageCode(_ value: Any?, fallback: String?) throws -> String? {
        guard let value, !(value is NSNull) else { return fallback }
        guard let value = value as? String,
              MeetingTranscriptionValidation.isValidLanguageCode(value)
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        return value
    }

    private static func finiteDouble(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double else { return nil }
        return number.intValue
    }

    private static func optionalString(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return value as? String
    }

    private static func optionalStrings(_ value: Any?) -> [String] {
        guard let value, !(value is NSNull) else { return [] }
        return value as? [String] ?? []
    }

    private static func absentOrNull(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}
