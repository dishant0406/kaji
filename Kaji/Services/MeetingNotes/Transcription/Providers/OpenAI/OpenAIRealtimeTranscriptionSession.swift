import Foundation

private struct OpenAIRealtimeCommit {
    let operationID: UUID
    let sampleRange: MeetingCanonicalSampleRange
    let providerEpoch: MeetingProviderEpoch
}

private struct OpenAIRealtimeItem {
    let commit: OpenAIRealtimeCommit
    var text: String
    var revision: Int
    var logprobs: [Double]
}

actor OpenAIRealtimeTranscriptionSession: MeetingTrackTranscriptionSession {
    private enum State {
        case idle
        case started
        case finished
        case cancelled
    }

    nonisolated let events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>

    private let route: MeetingTranscriptionRoute
    private let endpoint: URL
    private let context: MeetingTrackTranscriptionContextSnapshot
    private let bearerToken: String
    private let transport: any STTWebSocketTransporting
    private let audioRateConverter: any OpenAIAudioRateConverting
    private let configuration: OpenAIMeetingTranscriptionConfiguration
    private let nowMilliseconds: @Sendable () -> Int64
    private let eventChannel: MeetingTranscriptionProviderEventChannel
    private var state = State.idle
    private var sequenceNumber: Int64 = 0
    private var startedAtMilliseconds: Int64?
    private var rotationWarningEmitted = false
    private var awaitingCommittedItems: [OpenAIRealtimeCommit] = []
    private var items: [String: OpenAIRealtimeItem] = [:]
    private var eventTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    init(
        route: MeetingTranscriptionRoute,
        endpoint: URL,
        context: MeetingTrackTranscriptionContextSnapshot,
        bearerToken: String,
        transport: any STTWebSocketTransporting,
        audioRateConverter: any OpenAIAudioRateConverting,
        configuration: OpenAIMeetingTranscriptionConfiguration,
        nowMilliseconds: @escaping @Sendable () -> Int64
    ) {
        self.route = route
        self.endpoint = endpoint
        self.context = context
        self.bearerToken = bearerToken
        self.transport = transport
        self.audioRateConverter = audioRateConverter
        self.configuration = configuration
        self.nowMilliseconds = nowMilliseconds
        let eventChannel = MeetingTranscriptionProviderEventChannel()
        self.eventChannel = eventChannel
        events = eventChannel.events
    }

    func start() async throws {
        guard state == .idle else { throw OpenAIMeetingTranscriptionError.invalidState }
        state = .started
        startedAtMilliseconds = max(0, nowMilliseconds())
        emitSession(.starting)
        do {
            let stream = await transport.events()
            let endpoint = endpoint
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            try OpenAIEndpoint.authorize(&request, token: bearerToken, expected: endpoint)
            try await transport.connect(request: request)
            try await sendSessionUpdate()
            try await transport.ping()
            eventTask = Task { [weak self] in
                await self?.consume(stream)
            }
            pingTask = Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        return
                    }
                    await self?.sendKeepalive()
                }
            }
            emitSession(.ready)
        } catch {
            state = .finished
            await transport.cancel()
            emitFailure(commit: nil, code: "connection-failed", classification: .transient)
            eventChannel.finish()
            throw sanitize(error)
        }
    }

    func submit(_ packet: MeetingNormalizedAudioPacket) async throws {
        guard state == .started else { throw OpenAIMeetingTranscriptionError.invalidState }
        if packet.isEndOfStream {
            try await finish()
            return
        }
        try validate(packet)
        try validateRotation(packet)
        let audio = try audioRateConverter.pcm16Mono24kHz(from: packet)
        guard !audio.isEmpty,
              audio.count.isMultiple(of: 2),
              audio.count <= configuration.maximumRealtimeAudioBytesPerCommit
        else {
            throw audio.count > configuration.maximumRealtimeAudioBytesPerCommit ?
                OpenAIMeetingTranscriptionError.audioTooLarge : .invalidPacket
        }
        let commit = OpenAIRealtimeCommit(
            operationID: packet.operationID,
            sampleRange: packet.sampleRange,
            providerEpoch: packet.providerEpoch
        )
        guard awaitingCommittedItems.count < MeetingTranscriptionBufferPolicy.maximumOutstandingRealtimeCommits else {
            throw OpenAIMeetingTranscriptionError.invalidState
        }
        do {
            var offset = 0
            while offset < audio.count {
                let end = min(audio.count, offset + configuration.realtimeBase64ChunkBytes)
                let chunk = audio.subdata(in: offset ..< end)
                let encoded = chunk.base64EncodedString()
                guard encoded.utf8.count <= 350 * 1024 else {
                    throw OpenAIMeetingTranscriptionError.audioTooLarge
                }
                try await sendJSON([
                    "type": "input_audio_buffer.append",
                    "audio": encoded,
                ])
                offset = end
            }
            awaitingCommittedItems.append(commit)
            do {
                try await sendJSON(["type": "input_audio_buffer.commit"])
            } catch {
                _ = awaitingCommittedItems.popLast()
                throw error
            }
        } catch {
            let sanitized = sanitize(error)
            emitFailure(
                commit: commit,
                code: sanitized == .cancelled ? "cancelled" : "send-failed",
                classification: sanitized == .cancelled ? .cancelled : .transient
            )
            throw sanitized
        }
    }

    func finish() async throws {
        guard state == .started else {
            if state == .finished || state == .cancelled { return }
            throw OpenAIMeetingTranscriptionError.invalidState
        }
        emitSession(.draining)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(configuration.realtimeDrainSeconds))
        while !awaitingCommittedItems.isEmpty || !items.isEmpty, clock.now < deadline, state == .started {
            try await clock.sleep(for: .milliseconds(20))
        }
        guard state == .started else { throw OpenAIMeetingTranscriptionError.cancelled }
        if !awaitingCommittedItems.isEmpty || !items.isEmpty {
            emitWarning(code: "realtime-drain-timeout", message: "Realtime transcription did not finish before close.")
        }
        state = .finished
        pingTask?.cancel()
        do {
            try await transport.close(code: 1000, reason: nil)
        } catch {
            await transport.cancel()
        }
        eventTask?.cancel()
        emitSession(.completed)
        eventChannel.finish()
    }

    func cancel() async {
        guard state != .finished, state != .cancelled else { return }
        state = .cancelled
        pingTask?.cancel()
        eventTask?.cancel()
        awaitingCommittedItems.removeAll(keepingCapacity: false)
        items.removeAll(keepingCapacity: false)
        await transport.cancel()
        emitSession(.cancelled)
        eventChannel.finish()
    }

    private func validate(_ packet: MeetingNormalizedAudioPacket) throws {
        guard packet.sessionID == context.sessionID,
              packet.trackID == context.trackID,
              packet.source == context.source,
              packet.sampleRateHertz == context.canonicalSampleRateHertz,
              packet.channelCount == context.channelCount,
              packet.sampleRange.sampleRateHertz == context.canonicalSampleRateHertz,
              packet.encoding == .pcmSigned16LittleEndian
        else {
            throw OpenAIMeetingTranscriptionError.invalidPacket
        }
    }

    private func validateRotation(_ packet: MeetingNormalizedAudioPacket) throws {
        guard let startedAtMilliseconds else { throw OpenAIMeetingTranscriptionError.invalidState }
        let elapsed = max(0, nowMilliseconds() - startedAtMilliseconds)
        if elapsed >= 60 * 60 * 1000 {
            emitFailure(commit: OpenAIRealtimeCommit(
                operationID: packet.operationID,
                sampleRange: packet.sampleRange,
                providerEpoch: packet.providerEpoch
            ), code: "realtime-session-expired", classification: .permanent)
            throw OpenAIMeetingTranscriptionError.rotationRequired
        }
        if elapsed >= 55 * 60 * 1000, !rotationWarningEmitted {
            rotationWarningEmitted = true
            emitWarning(
                code: "realtime-session-rotation-required",
                message: "Rotate the realtime transcription session before the 60-minute limit."
            )
        }
    }

    private func sendSessionUpdate() async throws {
        var transcription: [String: Any] = ["model": route.modelID]
        if let language = route.languageCodes.first { transcription["language"] = language }
        var session: [String: Any] = [
            "type": "transcription",
            "audio": [
                "input": [
                    "format": ["type": "audio/pcm", "rate": 24000],
                    "transcription": transcription,
                    "turn_detection": NSNull(),
                ],
            ],
        ]
        if configuration.includeRealtimeLogprobs {
            session["include"] = ["item.input_audio_transcription.logprobs"]
        }
        try await sendJSON([
            "type": "session.update",
            "session": session,
        ])
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw OpenAIMeetingTranscriptionError.invalidConfiguration
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= 1024 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw OpenAIMeetingTranscriptionError.audioTooLarge
        }
        try await transport.send(.text(text))
    }

    private func consume(_ stream: AsyncStream<STTWebSocketEvent>) async {
        for await event in stream {
            guard state == .started else { return }
            switch event {
            case let .message(message):
                do {
                    try handle(message)
                } catch {
                    emitFailure(commit: nil, code: "protocol-error", classification: .permanent)
                    state = .finished
                    await transport.cancel()
                    eventChannel.finish()
                    return
                }
            case let .failed(error):
                emitFailure(
                    commit: nil,
                    code: error == .cancelled ? "cancelled" : "connection-failed",
                    classification: error == .cancelled ? .cancelled : .transient
                )
                state = error == .cancelled ? .cancelled : .finished
                eventChannel.finish()
                return
            case .closed:
                if state == .started {
                    emitFailure(commit: nil, code: "connection-closed", classification: .transient)
                    state = .finished
                    eventChannel.finish()
                    return
                }
            case .stateChanged,
                 .pong:
                break
            }
        }
    }

    private func handle(_ message: STTWebSocketMessage) throws {
        guard case let .text(text) = message,
              let data = text.data(using: .utf8),
              data.count <= 4 * 1024 * 1024
        else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        let event = try OpenAIRealtimeEventParser.parse(data)
        switch event {
        case let .committed(itemID):
            guard items[itemID] == nil, !awaitingCommittedItems.isEmpty else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            let commit = awaitingCommittedItems.removeFirst()
            items[itemID] = OpenAIRealtimeItem(commit: commit, text: "", revision: 0, logprobs: [])
        case let .delta(itemID, delta, logprobs):
            guard var item = items[itemID],
                  item.text.utf8.count <= 100_000 - delta.utf8.count
            else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            item.text += delta
            item.logprobs = try boundedLogprobs(item.logprobs + logprobs)
            guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                items[itemID] = item
                return
            }
            let utterance = try makeUtterance(item: item, text: item.text)
            let eventContext = try makeEventContext(
                eventID: OpenAIStableIdentity.uuid(operationID: item.commit.operationID, component: 100_000 + item.revision),
                operationID: item.commit.operationID,
                providerEpoch: item.commit.providerEpoch
            )
            eventChannel.send(.partial(MeetingTranscriptionPartialEvent(context: eventContext, utterance: utterance)))
            item.revision += 1
            items[itemID] = item
        case let .completed(itemID, transcript, logprobs):
            guard var item = items.removeValue(forKey: itemID) else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            item.logprobs = try boundedLogprobs(item.logprobs + logprobs)
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let utterance = try makeUtterance(item: item, text: transcript)
            let eventContext = try makeEventContext(
                eventID: OpenAIStableIdentity.uuid(operationID: item.commit.operationID, component: 200_000),
                operationID: item.commit.operationID,
                providerEpoch: item.commit.providerEpoch
            )
            eventChannel.send(.final(MeetingTranscriptionFinalEvent(context: eventContext, utterance: utterance)))
        case let .failed(itemID):
            guard let item = items.removeValue(forKey: itemID) else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            emitFailure(commit: item.commit, code: "item-transcription-failed", classification: .permanent)
        case let .rateLimit(limit, remaining, retryAfterMilliseconds):
            guard let eventContext = try? makeEventContext(
                eventID: UUID(),
                operationID: nil,
                providerEpoch: .initial
            ), let event = try? MeetingTranscriptionRateLimitEvent(
                context: eventContext,
                scope: "requests",
                limit: limit,
                remaining: remaining,
                retryAfterMilliseconds: retryAfterMilliseconds
            )
            else { return }
            eventChannel.send(.rateLimit(event))
        case .ignored:
            break
        case .serverError:
            emitFailure(commit: nil, code: "server-error", classification: .transient)
        }
    }

    private func makeUtterance(item: OpenAIRealtimeItem, text: String) throws -> MeetingTranscriptionUtterance {
        let confidence: Double? = if configuration.includeRealtimeLogprobs, !item.logprobs.isEmpty {
            min(1, max(0, exp(item.logprobs.reduce(0, +) / Double(item.logprobs.count))))
        } else {
            nil
        }
        return try MeetingTranscriptionUtterance(
            id: OpenAIStableIdentity.uuid(operationID: item.commit.operationID, component: 0),
            revision: item.revision,
            sampleRange: item.commit.sampleRange,
            text: text,
            confidence: confidence,
            language: route.languageCodes.first.map { try MeetingNormalizedLanguage(code: $0) },
            createdAtMilliseconds: max(context.startedAtMilliseconds, nowMilliseconds())
        )
    }

    private func boundedLogprobs(_ values: [Double]) throws -> [Double] {
        guard values.count <= 10000, values.allSatisfy({ $0.isFinite && $0 <= 0 && $0 >= -100 }) else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        return values
    }

    private func sendKeepalive() async {
        guard state == .started else { return }
        do {
            try await transport.ping()
        } catch {
            emitFailure(commit: nil, code: "keepalive-failed", classification: .transient)
        }
    }

    private func emitSession(_ sessionState: MeetingTranscriptionSessionState) {
        guard let eventContext = try? makeEventContext(
            eventID: UUID(),
            operationID: nil,
            providerEpoch: .initial
        ), let event = try? MeetingTranscriptionSessionEvent(context: eventContext, state: sessionState)
        else { return }
        eventChannel.send(.session(event))
    }

    private func emitWarning(code: String, message: String) {
        guard let eventContext = try? makeEventContext(
            eventID: UUID(),
            operationID: nil,
            providerEpoch: .initial
        ), let event = try? MeetingTranscriptionWarningEvent(
            context: eventContext,
            code: code,
            message: message,
            isRecoverable: true
        )
        else { return }
        eventChannel.send(.warning(event))
    }

    private func emitFailure(
        commit: OpenAIRealtimeCommit?,
        code: String,
        classification: MeetingTranscriptionFailureClassification
    ) {
        guard let eventContext = try? makeEventContext(
            eventID: UUID(),
            operationID: commit?.operationID,
            providerEpoch: commit?.providerEpoch ?? .initial
        ), let event = try? MeetingTranscriptionFailureEvent(
            context: eventContext,
            code: code,
            message: "OpenAI realtime transcription could not process the audio.",
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

    private func sanitize(_ error: Error) -> OpenAIMeetingTranscriptionError {
        if error is CancellationError { return .cancelled }
        if let error = error as? OpenAIMeetingTranscriptionError { return error }
        if let error = error as? STTNetworkError, error == .cancelled { return .cancelled }
        return .serviceUnavailable
    }
}

private enum OpenAIRealtimeEvent {
    case committed(itemID: String)
    case delta(itemID: String, delta: String, logprobs: [Double])
    case completed(itemID: String, transcript: String, logprobs: [Double])
    case failed(itemID: String)
    case rateLimit(limit: Int64?, remaining: Int64?, retryAfterMilliseconds: Int64?)
    case ignored
    case serverError
}

private enum OpenAIRealtimeEventParser {
    static func parse(_ data: Data) throws -> OpenAIRealtimeEvent {
        let object = try OpenAIJSON.object(data, maximumBytes: 4 * 1024 * 1024)
        guard let root = object as? [String: Any],
              let type = root["type"] as? String,
              type.utf8.count <= 128
        else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        switch type {
        case "session.created",
             "session.updated",
             "conversation.created",
             "conversation.item.created",
             "input_audio_buffer.cleared",
             "input_audio_buffer.speech_started",
             "input_audio_buffer.speech_stopped":
            return .ignored
        case "input_audio_buffer.committed":
            try OpenAIJSON.requireKeys(root, allowed: ["type", "event_id", "item_id", "previous_item_id"])
            return try .committed(itemID: itemID(root))
        case "conversation.item.input_audio_transcription.delta":
            try OpenAIJSON.requireKeys(
                root,
                allowed: ["type", "event_id", "item_id", "content_index", "delta", "logprobs"]
            )
            guard let delta = root["delta"] as? String,
                  !delta.isEmpty,
                  delta.utf8.count <= 100_000
            else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            return try .delta(itemID: itemID(root), delta: delta, logprobs: logprobs(root["logprobs"]))
        case "conversation.item.input_audio_transcription.completed":
            try OpenAIJSON.requireKeys(
                root,
                allowed: ["type", "event_id", "item_id", "content_index", "transcript", "usage", "logprobs"]
            )
            guard let transcript = root["transcript"] as? String,
                  transcript.utf8.count <= 100_000
            else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            return try .completed(
                itemID: itemID(root),
                transcript: transcript,
                logprobs: logprobs(root["logprobs"])
            )
        case "conversation.item.input_audio_transcription.failed":
            try OpenAIJSON.requireKeys(
                root,
                allowed: ["type", "event_id", "item_id", "content_index", "error"]
            )
            return try .failed(itemID: itemID(root))
        case "rate_limits.updated":
            try OpenAIJSON.requireKeys(root, allowed: ["type", "event_id", "rate_limits"])
            return try parseRateLimit(root["rate_limits"])
        case "error":
            try OpenAIJSON.requireKeys(root, allowed: ["type", "event_id", "error"])
            return .serverError
        default:
            return .ignored
        }
    }

    private static func itemID(_ root: [String: Any]) throws -> String {
        guard let value = root["item_id"] as? String,
              !value.isEmpty,
              value.utf8.count <= 128,
              value.utf8.allSatisfy({ byte in
                  byte >= 0x41 && byte <= 0x5A ||
                      byte >= 0x61 && byte <= 0x7A ||
                      byte >= 0x30 && byte <= 0x39 ||
                      byte == 0x2D || byte == 0x5F
              })
        else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        return value
    }

    private static func logprobs(_ value: Any?) throws -> [Double] {
        guard let value else { return [] }
        guard let values = value as? [Any], values.count <= 10000 else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        return try values.map { value in
            if let number = OpenAIJSON.double(value) {
                guard number.isFinite, number <= 0, number >= -100 else {
                    throw OpenAIMeetingTranscriptionError.invalidResponse
                }
                return number
            }
            guard let object = value as? [String: Any] else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            try OpenAIJSON.requireKeys(object, allowed: ["token", "logprob", "bytes"])
            guard let number = OpenAIJSON.double(object["logprob"]),
                  number.isFinite,
                  number <= 0,
                  number >= -100
            else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            return number
        }
    }

    private static func parseRateLimit(_ value: Any?) throws -> OpenAIRealtimeEvent {
        guard let values = value as? [Any], !values.isEmpty, values.count <= 16,
              let object = values.first as? [String: Any]
        else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        try OpenAIJSON.requireKeys(
            object,
            allowed: ["name", "limit", "remaining", "reset_seconds"]
        )
        let limit = try boundedInteger(object["limit"])
        let remaining = try boundedInteger(object["remaining"])
        let retrySeconds = OpenAIJSON.double(object["reset_seconds"])
        guard retrySeconds.map({ $0 >= 0 && $0 <= 3600 }) ?? true else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        let retry = retrySeconds.map { Int64($0 * 1000) }
        guard limit.map({ $0 >= 0 }) ?? true,
              remaining.map({ $0 >= 0 }) ?? true,
              limit.map({ maximum in remaining.map { $0 <= maximum } ?? true }) ?? true
        else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        return .rateLimit(limit: limit, remaining: remaining, retryAfterMilliseconds: retry)
    }

    private static func boundedInteger(_ value: Any?) throws -> Int64? {
        guard let value else { return nil }
        guard let number = OpenAIJSON.double(value),
              number >= 0,
              number <= Double(Int64.max),
              number.rounded(.towardZero) == number
        else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        return Int64(number)
    }
}
