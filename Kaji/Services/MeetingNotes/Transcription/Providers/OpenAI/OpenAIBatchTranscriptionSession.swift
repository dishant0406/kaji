import Foundation

private struct OpenAIBatchWord {
    let text: String
    let startSeconds: Double
    let endSeconds: Double
}

private struct OpenAIBatchSegment {
    let text: String
    let startSeconds: Double?
    let endSeconds: Double?
    let speaker: String?
    let words: [OpenAIBatchWord]
}

private struct OpenAIHTTPFailure {
    let error: OpenAIMeetingTranscriptionError
    let classification: MeetingTranscriptionFailureClassification
    let code: String
}

actor OpenAIBatchTranscriptionSession: MeetingTrackTranscriptionSession {
    private enum State {
        case idle
        case started
        case finished
        case cancelled
    }

    nonisolated let events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>

    private let route: MeetingTranscriptionRoute
    private let context: MeetingTrackTranscriptionContextSnapshot
    private let bearerToken: String
    private let transport: any OpenAIHTTPTransporting
    private let configuration: OpenAIMeetingTranscriptionConfiguration
    private let endpoint: URL
    private let nowMilliseconds: @Sendable () -> Int64
    private let eventChannel: MeetingTranscriptionProviderEventChannel
    private var state = State.idle
    private var sequenceNumber: Int64 = 0
    private var submittedAudio = false

    init(
        route: MeetingTranscriptionRoute,
        endpoint: URL,
        context: MeetingTrackTranscriptionContextSnapshot,
        bearerToken: String,
        transport: any OpenAIHTTPTransporting,
        configuration: OpenAIMeetingTranscriptionConfiguration,
        nowMilliseconds: @escaping @Sendable () -> Int64
    ) {
        self.route = route
        self.endpoint = endpoint
        self.context = context
        self.bearerToken = bearerToken
        self.transport = transport
        self.configuration = configuration
        self.nowMilliseconds = nowMilliseconds
        let eventChannel = MeetingTranscriptionProviderEventChannel()
        self.eventChannel = eventChannel
        events = eventChannel.events
    }

    func start() async throws {
        guard state == .idle else { throw OpenAIMeetingTranscriptionError.invalidState }
        state = .started
        emitSession(.starting)
        emitSession(.ready)
    }

    func submit(_ packet: MeetingNormalizedAudioPacket) async throws {
        guard state == .started else { throw OpenAIMeetingTranscriptionError.invalidState }
        if packet.isEndOfStream {
            try await finish()
            return
        }
        try validate(packet)
        submittedAudio = true
        do {
            try Task.checkCancellation()
            let endpoint = endpoint
            let request = try makeRequest(packet: packet, endpoint: endpoint)
            let response = try await transport.execute(request)
            try Task.checkCancellation()
            guard state == .started else { throw OpenAIMeetingTranscriptionError.cancelled }
            try OpenAIEndpoint.validateFinal(response.finalURL, expected: endpoint)
            guard response.body.count <= configuration.maximumResponseBytes else {
                throw OpenAIMeetingTranscriptionError.responseTooLarge
            }
            guard 200 ... 299 ~= response.statusCode else {
                try handleHTTPFailure(response, packet: packet)
                return
            }
            emitRateLimitHeaders(response.headers, packet: packet)
            if streamsResponse {
                try emitStreamedResponse(response.body, packet: packet)
            } else {
                try emitResponse(response, packet: packet)
            }
        } catch is CancellationError {
            emitFailure(packet: packet, code: "cancelled", classification: .cancelled)
            throw OpenAIMeetingTranscriptionError.cancelled
        } catch let error as OpenAIMeetingTranscriptionError {
            if error != .rateLimited,
               error != .authenticationFailed,
               error != .authorizationFailed,
               error != .quotaExceeded,
               error != .serviceUnavailable,
               error != .cancelled
            {
                emitFailure(packet: packet, code: failureCode(error), classification: classification(error))
            }
            throw error
        } catch let error as STTNetworkError {
            let classification: MeetingTranscriptionFailureClassification = error == .cancelled ? .cancelled : .transient
            emitFailure(packet: packet, code: "network-failure", classification: classification)
            throw error == .cancelled ? OpenAIMeetingTranscriptionError.cancelled : .serviceUnavailable
        } catch {
            emitFailure(packet: packet, code: "transcription-failed", classification: .permanent)
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
    }

    func finish() async throws {
        guard state == .started else {
            if state == .finished || state == .cancelled { return }
            throw OpenAIMeetingTranscriptionError.invalidState
        }
        if route.diarizationEnabled, !submittedAudio {
            emitFailure(packet: nil, code: "audio-batch-required", classification: .invalidRequest)
            throw OpenAIMeetingTranscriptionError.audioBatchRequired
        }
        emitSession(.draining)
        state = .finished
        emitSession(.completed)
        eventChannel.finish()
    }

    func cancel() async {
        guard state != .finished, state != .cancelled else { return }
        state = .cancelled
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
              packet.encoding == .pcmSigned16LittleEndian || packet.encoding == .wav
        else {
            throw OpenAIMeetingTranscriptionError.invalidPacket
        }
        guard packet.bytes.count < Self.maximumAudioPayloadBytes else {
            throw OpenAIMeetingTranscriptionError.audioTooLarge
        }
        if packet.encoding == .wav {
            guard packet.bytes.count >= 44,
                  packet.bytes.prefix(4) == Data("RIFF".utf8),
                  packet.bytes.dropFirst(8).prefix(4) == Data("WAVE".utf8),
                  littleEndianUInt16(packet.bytes, offset: 20) == 1,
                  littleEndianUInt16(packet.bytes, offset: 22) == UInt16(packet.channelCount),
                  littleEndianUInt32(packet.bytes, offset: 24) == UInt32(packet.sampleRateHertz),
                  littleEndianUInt16(packet.bytes, offset: 34) == 16,
                  littleEndianUInt32(packet.bytes, offset: 40) == UInt32(packet.bytes.count - 44)
            else {
                throw OpenAIMeetingTranscriptionError.invalidPacket
            }
        }
    }

    private func makeRequest(packet: MeetingNormalizedAudioPacket, endpoint: URL) throws -> URLRequest {
        let wav = try wavData(packet)
        let boundary = "KajiOpenAI\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var multipart = OpenAIMultipartBody(boundary: boundary, maximumBytes: OpenAIMeetingTranscriptionProvider.maximumUploadBytes)
        try multipart.appendField(name: "model", value: route.modelID)
        if route.diarizationEnabled {
            try multipart.appendField(name: "response_format", value: "diarized_json")
            try multipart.appendField(name: "chunking_strategy", value: "auto")
        } else {
            try multipart.appendField(name: "response_format", value: "json")
        }
        if let language = route.languageCodes.first {
            try multipart.appendField(name: "language", value: language)
        }
        if !route.diarizationEnabled, !context.keyterms.isEmpty {
            let prompt = context.keyterms.joined(separator: ", ")
            guard prompt.count <= 4000 else { throw OpenAIMeetingTranscriptionError.invalidPacket }
            try multipart.appendField(name: "prompt", value: prompt)
        }
        if streamsResponse {
            try multipart.appendField(name: "stream", value: "true")
        }
        try multipart.appendFile(name: "file", filename: "meeting.wav", contentType: "audio/wav", data: wav)
        let body = try multipart.finish()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(
            streamsResponse ? "text/event-stream" : "application/json, text/plain",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        try OpenAIEndpoint.authorize(&request, token: bearerToken, expected: endpoint)
        return request
    }

    private func wavData(_ packet: MeetingNormalizedAudioPacket) throws -> Data {
        if packet.encoding == .wav { return packet.bytes }
        guard packet.channelCount <= 2,
              packet.sampleRateHertz <= Int(UInt32.max),
              packet.bytes.count <= Self.maximumAudioPayloadBytes - 44,
              packet.bytes.count.isMultiple(of: packet.channelCount * 2)
        else {
            throw OpenAIMeetingTranscriptionError.invalidPacket
        }
        var data = Data(capacity: packet.bytes.count + 44)
        data.append(Data("RIFF".utf8))
        append(UInt32(36 + packet.bytes.count), to: &data)
        data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(packet.channelCount), to: &data)
        append(UInt32(packet.sampleRateHertz), to: &data)
        append(UInt32(packet.sampleRateHertz * packet.channelCount * 2), to: &data)
        append(UInt16(packet.channelCount * 2), to: &data)
        append(UInt16(16), to: &data)
        data.append(Data("data".utf8))
        append(UInt32(packet.bytes.count), to: &data)
        data.append(packet.bytes)
        return data
    }

    private func append(_ value: some FixedWidthInteger, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private func littleEndianUInt16(_ data: Data, offset: Int) -> UInt16? {
        guard offset >= 0, offset <= data.count - 2 else { return nil }
        return data.withUnsafeBytes {
            UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
        }
    }

    private func littleEndianUInt32(_ data: Data, offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return data.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }

    private func emitResponse(_ response: OpenAIHTTPResponse, packet: MeetingNormalizedAudioPacket) throws {
        let segments: [OpenAIBatchSegment]
        let contentType = response.headers["content-type"]?.lowercased() ?? "application/json"
        if contentType.hasPrefix("text/plain"), !route.diarizationEnabled {
            guard let text = String(data: response.body, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.utf8.count == response.body.count,
                  text.count <= 100_000,
                  !text.contains("\0")
            else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            segments = [OpenAIBatchSegment(text: text, startSeconds: nil, endSeconds: nil, speaker: nil, words: [])]
        } else {
            guard contentType.hasPrefix("application/json") else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            segments = try OpenAIBatchResponseParser.parse(response.body, diarized: route.diarizationEnabled)
        }
        for (index, segment) in segments.enumerated() {
            let utterance = try makeUtterance(segment: segment, index: index, revision: 0, packet: packet)
            let eventContext = try makeEventContext(
                eventID: utterance.id,
                operationID: packet.operationID,
                providerEpoch: packet.providerEpoch
            )
            eventChannel.send(.final(MeetingTranscriptionFinalEvent(context: eventContext, utterance: utterance)))
        }
    }

    private func emitStreamedResponse(_ data: Data, packet: MeetingNormalizedAudioPacket) throws {
        var decoder = try STTServerSentEventDecoder(limits: STTSSEDecoderLimits(
            maximumLineBytes: 64 * 1024,
            maximumEventDataBytes: min(configuration.maximumResponseBytes, 1024 * 1024),
            maximumBufferedBytes: configuration.maximumResponseBytes,
            maximumEventsPerBatch: 4096
        ))
        var events = try decoder.append(data)
        try events.append(contentsOf: decoder.finish())
        guard events.count <= 4096 else { throw OpenAIMeetingTranscriptionError.invalidResponse }
        var text = ""
        var revision = 0
        var emittedFinal = false
        var emittedSegmentCount = 0
        for event in events {
            if event.data == "[DONE]" { continue }
            let update = try OpenAISSEPayloadParser.parse(Data(event.data.utf8))
            switch update {
            case let .delta(delta):
                guard text.utf8.count <= 100_000 - delta.utf8.count else {
                    throw OpenAIMeetingTranscriptionError.responseTooLarge
                }
                text += delta
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let segment = OpenAIBatchSegment(text: text, startSeconds: nil, endSeconds: nil, speaker: nil, words: [])
                let utterance = try makeUtterance(segment: segment, index: 0, revision: revision, packet: packet)
                let eventContext = try makeEventContext(
                    eventID: OpenAIStableIdentity.uuid(operationID: packet.operationID, component: 100_000 + revision),
                    operationID: packet.operationID,
                    providerEpoch: packet.providerEpoch
                )
                eventChannel.send(.partial(MeetingTranscriptionPartialEvent(context: eventContext, utterance: utterance)))
                revision += 1
            case let .segment(segment):
                guard route.diarizationEnabled else { throw OpenAIMeetingTranscriptionError.invalidResponse }
                let utterance = try makeUtterance(
                    segment: segment,
                    index: emittedSegmentCount,
                    revision: 0,
                    packet: packet
                )
                let eventContext = try makeEventContext(
                    eventID: utterance.id,
                    operationID: packet.operationID,
                    providerEpoch: packet.providerEpoch
                )
                eventChannel.send(.final(MeetingTranscriptionFinalEvent(context: eventContext, utterance: utterance)))
                emittedSegmentCount += 1
                emittedFinal = true
            case let .done(doneText):
                if emittedSegmentCount > 0 { continue }
                let finalText = doneText ?? text
                let segment = OpenAIBatchSegment(text: finalText, startSeconds: nil, endSeconds: nil, speaker: nil, words: [])
                let utterance = try makeUtterance(segment: segment, index: 0, revision: revision, packet: packet)
                let eventContext = try makeEventContext(
                    eventID: OpenAIStableIdentity.uuid(operationID: packet.operationID, component: 200_000),
                    operationID: packet.operationID,
                    providerEpoch: packet.providerEpoch
                )
                eventChannel.send(.final(MeetingTranscriptionFinalEvent(context: eventContext, utterance: utterance)))
                emittedFinal = true
            }
        }
        if !emittedFinal, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let segment = OpenAIBatchSegment(text: text, startSeconds: nil, endSeconds: nil, speaker: nil, words: [])
            let utterance = try makeUtterance(segment: segment, index: 0, revision: revision, packet: packet)
            let eventContext = try makeEventContext(
                eventID: OpenAIStableIdentity.uuid(operationID: packet.operationID, component: 200_000),
                operationID: packet.operationID,
                providerEpoch: packet.providerEpoch
            )
            eventChannel.send(.final(MeetingTranscriptionFinalEvent(context: eventContext, utterance: utterance)))
        } else if !emittedFinal {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
    }

    private func makeUtterance(
        segment: OpenAIBatchSegment,
        index: Int,
        revision: Int,
        packet: MeetingNormalizedAudioPacket
    ) throws -> MeetingTranscriptionUtterance {
        let range = try sampleRange(start: segment.startSeconds, end: segment.endSeconds, packet: packet)
        let speaker = try segment.speaker.map { value in
            let identifier = OpenAIBatchResponseParser.speakerIdentifier(value)
            return try MeetingNormalizedSpeaker(id: identifier, label: String(value.prefix(120)))
        }
        let words = try segment.words.enumerated().map { wordIndex, word in
            try MeetingNormalizedWord(
                id: OpenAIStableIdentity.uuid(operationID: packet.operationID, component: (index + 1) * 10000 + wordIndex),
                text: word.text,
                sampleRange: sampleRange(start: word.startSeconds, end: word.endSeconds, packet: packet),
                speakerID: speaker?.id,
                languageCode: route.languageCodes.first
            )
        }
        return try MeetingTranscriptionUtterance(
            id: OpenAIStableIdentity.uuid(operationID: packet.operationID, component: index),
            revision: revision,
            sampleRange: range,
            text: segment.text,
            words: words,
            speaker: speaker,
            language: route.languageCodes.first.map { try MeetingNormalizedLanguage(code: $0) },
            createdAtMilliseconds: max(context.startedAtMilliseconds, nowMilliseconds())
        )
    }

    private func sampleRange(
        start: Double?,
        end: Double?,
        packet: MeetingNormalizedAudioPacket
    ) throws -> MeetingCanonicalSampleRange {
        guard let start, let end else { return packet.sampleRange }
        let maximumDuration = Double(packet.sampleRange.frameCount) / Double(packet.sampleRateHertz)
        guard start.isFinite,
              end.isFinite,
              start >= 0,
              end > start,
              start <= maximumDuration + 1,
              end <= maximumDuration + 1
        else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        let startOffset = Int64((start * Double(packet.sampleRateHertz)).rounded(.down))
        let endOffset = Int64((end * Double(packet.sampleRateHertz)).rounded(.up))
        let boundedStart = min(packet.sampleRange.endFrame - 1, packet.sampleRange.startFrame + startOffset)
        let boundedEnd = min(packet.sampleRange.endFrame, packet.sampleRange.startFrame + max(startOffset + 1, endOffset))
        guard boundedEnd > boundedStart else { throw OpenAIMeetingTranscriptionError.invalidResponse }
        return try MeetingCanonicalSampleRange(
            startFrame: boundedStart,
            endFrame: boundedEnd,
            sampleRateHertz: packet.sampleRateHertz
        )
    }

    private func handleHTTPFailure(_ response: OpenAIHTTPResponse, packet: MeetingNormalizedAudioPacket) throws {
        let errorCode = OpenAIErrorResponseParser.code(response.body)
        let retry = STTRetryAfterParser.delay(from: response.headers["retry-after"]).map { Int64($0 * 1000) }
        let result = if response.statusCode == 401 {
            OpenAIHTTPFailure(
                error: .authenticationFailed,
                classification: .authentication,
                code: "authentication-failed"
            )
        } else if response.statusCode == 403 {
            OpenAIHTTPFailure(error: .authorizationFailed, classification: .authorization, code: "authorization-failed")
        } else if response.statusCode == 429, errorCode == "insufficient_quota" {
            OpenAIHTTPFailure(error: .quotaExceeded, classification: .quotaExceeded, code: "quota-exceeded")
        } else if response.statusCode == 429 {
            OpenAIHTTPFailure(error: .rateLimited, classification: .rateLimited, code: "rate-limited")
        } else if [500, 502, 503, 504].contains(response.statusCode) {
            OpenAIHTTPFailure(error: .serviceUnavailable, classification: .transient, code: "service-unavailable")
        } else {
            OpenAIHTTPFailure(error: .invalidResponse, classification: .invalidRequest, code: "request-rejected")
        }
        if response.statusCode == 429 {
            emitRateLimit(packet: packet, retryAfterMilliseconds: retry)
        }
        emitFailure(
            packet: packet,
            code: result.code,
            classification: result.classification,
            retryAfterMilliseconds: retry
        )
        throw result.error
    }

    private func emitRateLimitHeaders(_ headers: [String: String], packet: MeetingNormalizedAudioPacket) {
        let limit = headers["x-ratelimit-limit-requests"].flatMap(Int64.init)
        let remaining = headers["x-ratelimit-remaining-requests"].flatMap(Int64.init)
        guard limit != nil || remaining != nil else { return }
        guard let eventContext = try? makeEventContext(
            eventID: UUID(),
            operationID: packet.operationID,
            providerEpoch: packet.providerEpoch
        ), let event = try? MeetingTranscriptionRateLimitEvent(
            context: eventContext,
            scope: "requests",
            limit: limit,
            remaining: remaining
        )
        else { return }
        eventChannel.send(.rateLimit(event))
    }

    private func emitRateLimit(packet: MeetingNormalizedAudioPacket, retryAfterMilliseconds: Int64?) {
        guard let eventContext = try? makeEventContext(
            eventID: UUID(),
            operationID: packet.operationID,
            providerEpoch: packet.providerEpoch
        ), let event = try? MeetingTranscriptionRateLimitEvent(
            context: eventContext,
            scope: "requests",
            retryAfterMilliseconds: retryAfterMilliseconds
        )
        else { return }
        eventChannel.send(.rateLimit(event))
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

    private func emitFailure(
        packet: MeetingNormalizedAudioPacket?,
        code: String,
        classification: MeetingTranscriptionFailureClassification,
        retryAfterMilliseconds: Int64? = nil
    ) {
        guard let eventContext = try? makeEventContext(
            eventID: UUID(),
            operationID: packet?.operationID,
            providerEpoch: packet?.providerEpoch ?? .initial
        ), let event = try? MeetingTranscriptionFailureEvent(
            context: eventContext,
            code: code,
            message: "OpenAI transcription could not process the audio.",
            classification: classification,
            retryAfterMilliseconds: retryAfterMilliseconds
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

    private func failureCode(_ error: OpenAIMeetingTranscriptionError) -> String {
        switch error {
        case .audioTooLarge: "audio-too-large"
        case .responseTooLarge: "response-too-large"
        case .invalidPacket: "invalid-audio"
        default: "invalid-response"
        }
    }

    private func classification(_ error: OpenAIMeetingTranscriptionError) -> MeetingTranscriptionFailureClassification {
        switch error {
        case .invalidPacket,
             .audioTooLarge,
             .audioBatchRequired: .invalidRequest
        case .responseTooLarge,
             .invalidResponse: .permanent
        default: .unavailable
        }
    }

    private static let maximumAudioPayloadBytes = OpenAIMeetingTranscriptionProvider.maximumUploadBytes - 1024

    private var streamsResponse: Bool {
        configuration.streamBatchResponses
    }
}

private struct OpenAIMultipartBody {
    let boundary: String
    let maximumBytes: Int
    private var data = Data()
    private var finished = false

    init(boundary: String, maximumBytes: Int) {
        self.boundary = boundary
        self.maximumBytes = maximumBytes
    }

    mutating func appendField(name: String, value: String) throws {
        guard !finished,
              Self.validToken(name),
              value.utf8.count <= 100_000,
              !value.contains("\0"),
              !value.contains("\r\n--\(boundary)")
        else {
            throw OpenAIMeetingTranscriptionError.invalidPacket
        }
        try append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func appendFile(name: String, filename: String, contentType: String, data file: Data) throws {
        guard !finished,
              Self.validToken(name),
              Self.validToken(filename),
              contentType == "audio/wav"
        else {
            throw OpenAIMeetingTranscriptionError.invalidPacket
        }
        let disposition = "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        let headers = disposition + "Content-Type: \(contentType)\r\n\r\n"
        try append(Data(headers.utf8))
        try append(file)
        try append(Data("\r\n".utf8))
    }

    mutating func finish() throws -> Data {
        guard !finished else { throw OpenAIMeetingTranscriptionError.invalidState }
        try append(Data("--\(boundary)--\r\n".utf8))
        finished = true
        return data
    }

    private mutating func append(_ value: Data) throws {
        guard value.count <= maximumBytes - data.count else {
            data.removeAll(keepingCapacity: false)
            throw OpenAIMeetingTranscriptionError.audioTooLarge
        }
        data.append(value)
    }

    private static func validToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 100 && value.utf8.allSatisfy { byte in
            byte >= 0x41 && byte <= 0x5A ||
                byte >= 0x61 && byte <= 0x7A ||
                byte >= 0x30 && byte <= 0x39 ||
                byte == 0x2D || byte == 0x2E || byte == 0x5B || byte == 0x5D || byte == 0x5F
        }
    }
}

private enum OpenAIBatchResponseParser {
    static func parse(_ data: Data, diarized: Bool) throws -> [OpenAIBatchSegment] {
        let object = try OpenAIJSON.object(data, maximumBytes: 8 * 1024 * 1024)
        guard let root = object as? [String: Any] else { throw OpenAIMeetingTranscriptionError.invalidResponse }
        try OpenAIJSON.requireKeys(
            root,
            allowed: ["task", "language", "duration", "text", "words", "segments", "usage"]
        )
        if diarized {
            guard let values = root["segments"] as? [Any], !values.isEmpty, values.count <= 10000 else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            return try values.map(parseSegment)
        }
        guard let text = root["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= 100_000
        else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        let words = try parseWords(root["words"])
        return [OpenAIBatchSegment(text: text, startSeconds: nil, endSeconds: nil, speaker: nil, words: words)]
    }

    static func speakerIdentifier(_ value: String) -> String {
        let normalized = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let collapsed = String(normalized).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return "speaker-\(String(collapsed.prefix(100)).isEmpty ? "unknown" : String(collapsed.prefix(100)))"
    }

    static func parseSegment(_ value: Any) throws -> OpenAIBatchSegment {
        guard let object = value as? [String: Any] else { throw OpenAIMeetingTranscriptionError.invalidResponse }
        try OpenAIJSON.requireKeys(
            object,
            allowed: [
                "id", "seek", "start", "end", "text", "tokens", "temperature", "avg_logprob",
                "compression_ratio", "no_speech_prob", "speaker", "type", "words",
            ]
        )
        guard let text = object["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= 100_000,
              let start = OpenAIJSON.double(object["start"]),
              let end = OpenAIJSON.double(object["end"]),
              start.isFinite,
              end.isFinite,
              start >= 0,
              end > start,
              let speaker = object["speaker"] as? String,
              !speaker.isEmpty,
              speaker.count <= 120
        else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        return try OpenAIBatchSegment(
            text: text,
            startSeconds: start,
            endSeconds: end,
            speaker: speaker,
            words: parseWords(object["words"])
        )
    }

    private static func parseWords(_ value: Any?) throws -> [OpenAIBatchWord] {
        guard let value else { return [] }
        guard let values = value as? [Any], values.count <= 10000 else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        return try values.map { value in
            guard let object = value as? [String: Any] else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            try OpenAIJSON.requireKeys(object, allowed: ["word", "start", "end", "speaker"])
            guard let word = object["word"] as? String,
                  !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  word.count <= 1000,
                  let start = OpenAIJSON.double(object["start"]),
                  let end = OpenAIJSON.double(object["end"]),
                  start.isFinite,
                  end.isFinite,
                  start >= 0,
                  end > start
            else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            return OpenAIBatchWord(text: word, startSeconds: start, endSeconds: end)
        }
    }
}

private enum OpenAISSEUpdate {
    case delta(String)
    case segment(OpenAIBatchSegment)
    case done(String?)
}

private enum OpenAISSEPayloadParser {
    static func parse(_ data: Data) throws -> OpenAISSEUpdate {
        let object = try OpenAIJSON.object(data, maximumBytes: 1024 * 1024)
        guard let root = object as? [String: Any], let type = root["type"] as? String else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        switch type {
        case "transcript.text.delta",
             "transcription.text.delta":
            try OpenAIJSON.requireKeys(root, allowed: ["type", "delta", "logprobs", "segment_id"])
            guard let delta = root["delta"] as? String, !delta.isEmpty, delta.count <= 100_000 else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            try validateSegmentID(root["segment_id"])
            return .delta(delta)
        case "transcript.text.segment":
            try OpenAIJSON.requireKeys(root, allowed: ["type", "id", "start", "end", "text", "speaker"])
            return try .segment(OpenAIBatchResponseParser.parseSegment(root))
        case "transcript.text.done",
             "transcription.text.done":
            try OpenAIJSON.requireKeys(root, allowed: ["type", "text", "usage", "logprobs"])
            let text = root["text"] as? String
            guard text.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 100_000 }) ?? true else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            return .done(text)
        default:
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
    }

    private static func validateSegmentID(_ value: Any?) throws {
        guard let value else { return }
        guard let value = value as? String,
              !value.isEmpty,
              value.utf8.count <= 128,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              })
        else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
    }
}

private enum OpenAIErrorResponseParser {
    static func code(_ data: Data) -> String? {
        guard data.count <= 64 * 1024,
              let object = try? OpenAIJSON.object(data, maximumBytes: 64 * 1024),
              let root = object as? [String: Any],
              Set(root.keys).isSubset(of: ["error"]),
              let error = root["error"] as? [String: Any],
              Set(error.keys).isSubset(of: ["message", "type", "param", "code"]),
              let code = error["code"] as? String,
              code.count <= 128
        else { return nil }
        return code
    }
}

enum OpenAIJSON {
    static func object(_ data: Data, maximumBytes: Int) throws -> Any {
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw data.count > maximumBytes ? OpenAIMeetingTranscriptionError.responseTooLarge : .invalidResponse
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        var remainingValues = 50000
        try validate(object, depth: 0, remainingValues: &remainingValues)
        return object
    }

    static func requireKeys(_ object: [String: Any], allowed: Set<String>) throws {
        guard object.count <= allowed.count, Set(object.keys).isSubset(of: allowed) else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
    }

    static func double(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    private static func validate(_ value: Any, depth: Int, remainingValues: inout Int) throws {
        guard depth <= 12, remainingValues > 0 else { throw OpenAIMeetingTranscriptionError.invalidResponse }
        remainingValues -= 1
        if let object = value as? [String: Any] {
            guard object.count <= 256,
                  object.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 })
            else { throw OpenAIMeetingTranscriptionError.invalidResponse }
            for nested in object.values {
                try validate(nested, depth: depth + 1, remainingValues: &remainingValues)
            }
        } else if let array = value as? [Any] {
            guard array.count <= 10000 else { throw OpenAIMeetingTranscriptionError.invalidResponse }
            for nested in array {
                try validate(nested, depth: depth + 1, remainingValues: &remainingValues)
            }
        } else if let string = value as? String {
            guard string.utf8.count <= 1_000_000, !string.contains("\0") else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
        } else if let number = value as? NSNumber {
            guard CFGetTypeID(number) == CFBooleanGetTypeID() || number.doubleValue.isFinite else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
        } else if !(value is NSNull) {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
    }
}
