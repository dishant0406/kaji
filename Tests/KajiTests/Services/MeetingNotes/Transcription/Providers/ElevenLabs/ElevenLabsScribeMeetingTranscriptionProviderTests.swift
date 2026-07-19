import Foundation
import Testing

@testable import Kaji
private enum ElevenLabsTestModels {
    static let batch = "scribe_v2"
    static let realtime = "scribe_v2_realtime"
}

private func elevenLabsTestEndpoint(regionID: String = "global") throws -> MeetingTranscriptionEndpointSnapshot {
    try MeetingTranscriptionEndpointProfile(
        providerID: ElevenLabsScribeMeetingTranscriptionProvider.providerID,
        displayName: "ElevenLabs Test",
        variant: .elevenLabsScribe,
        regionID: regionID,
        restBaseURL: "https://api.elevenlabs.io",
        webSocketBaseURL: "wss://api.elevenlabs.io",
        discovery: MeetingTranscriptionModelDiscoveryConfiguration(kind: .manual),
        source: .builtIn
    ).snapshot
}

private func elevenLabsTestModels() throws -> [MeetingDiscoveredTranscriptionModel] {
    [
        try MeetingDiscoveredTranscriptionModel(
            id: ElevenLabsTestModels.batch,
            displayName: "Batch",
            modes: [.cloudBatch],
            languageCodes: ["en", "eng", "fr", "fra"],
            capabilityConfidence: .manual
        ),
        try MeetingDiscoveredTranscriptionModel(
            id: ElevenLabsTestModels.realtime,
            displayName: "Realtime",
            modes: [.cloudRealtime],
            languageCodes: ["en", "eng", "fr", "fra"],
            capabilityConfidence: .manual
        ),
    ]
}


@Suite("ElevenLabs Scribe meeting transcription provider")
struct ElevenLabsScribeMeetingTranscriptionProviderTests {
    @Test("descriptors publish batch realtime privacy endpoint and capability bounds")
    func capabilities() throws {
        let provider = try makeProvider()
        let batch = try #require(provider.descriptor.model(id: ElevenLabsTestModels.batch))
        let realtime = try #require(provider.descriptor.model(id: ElevenLabsTestModels.realtime))

        #expect(batch.capabilities.modes == [.cloudBatch])
        #expect(batch.capabilities.diarization.availability == .supported)
        #expect(batch.capabilities.timing.availability == .supported)
        #expect(batch.capabilities.confidence.availability == .supported)
        #expect(batch.metadata["capabilityConfidence"] == "manual")
        #expect(realtime.capabilities.modes == [.cloudRealtime])
        #expect(realtime.capabilities.partialResults.availability == .supported)
        #expect(realtime.capabilities.diarization.availability == .unsupported)
        #expect(batch.supportedLanguageCodes == ["en", "eng", "fr", "fra"])
        #expect(batch.privacy.supportedRetention == [.providerDefault, .none])
        #expect(batch.regions.map(\.id) == ["global"])
    }

    @Test("keyterm policies enforce documented batch and realtime bounds")
    func keytermBounds() throws {
        try ElevenLabsScribeKeytermPolicy.validateBatch(Array(repeating: "term", count: 1000).enumerated().map { "\($0.offset)\($0.element)" })
        try ElevenLabsScribeKeytermPolicy.validateRealtime(Array(0 ..< 50).map { "term\($0)" })

        #expect(throws: ElevenLabsScribeError.self) {
            try ElevenLabsScribeKeytermPolicy.validateBatch(Array(0 ... 1000).map { "term\($0)" })
        }
        #expect(throws: ElevenLabsScribeError.self) {
            try ElevenLabsScribeKeytermPolicy.validateBatch([String(repeating: "x", count: 51)])
        }
        #expect(throws: ElevenLabsScribeError.self) {
            try ElevenLabsScribeKeytermPolicy.validateRealtime(Array(0 ... 50).map { "term\($0)" })
        }
        #expect(throws: ElevenLabsScribeError.self) {
            try ElevenLabsScribeKeytermPolicy.validateRealtime([String(repeating: "x", count: 21)])
        }
        #expect(throws: ElevenLabsScribeError.self) {
            try ElevenLabsScribeKeytermPolicy.validateBatch(["unsafe<term"])
        }
    }

    @Test("batch sends strict WAV multipart diarization speaker and no-verbatim fields")
    func batchMultipartAndDiarization() async throws {
        let http = FakeElevenLabsHTTPTransport(responses: [try successResponse(batchTranscript())])
        let provider = try makeProvider(
            http: http,
            batchOptions: ElevenLabsScribeBatchOptions(
                tagAudioEvents: true,
                noVerbatim: true,
                speakerCount: 2
            )
        )
        let route = try provider.route(mode: .cloudBatch, languageCode: "eng", diarizationEnabled: true)
        let context = try makeContext(keyterms: ["Kaji", "Muxy"])
        let session = try await provider.makeSession(route: route, context: context)
        let recorder = ElevenLabsEventRecorder(stream: session.events)

        try await session.start()
        try await session.submit(makePacket())
        try await session.finish()
        let request = try #require(await http.requests().first)
        let body = try #require(request.httpBody)
        let wire = String(decoding: body, as: UTF8.self)

        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == "api.elevenlabs.io")
        #expect(request.url?.path == "/v1/speech-to-text")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "test-api-key")
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        #expect(request.value(forHTTPHeaderField: "Pragma") == "no-cache")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=KajiBoundary")
        #expect(wire.contains("name=\"file\"; filename=\"audio.wav\""))
        #expect(wire.contains("Content-Type: audio/wav"))
        #expect(body.range(of: Data("RIFF".utf8)) != nil)
        #expect(wire.contains("name=\"model_id\"\r\n\r\nscribe_v2"))
        #expect(wire.contains("name=\"language_code\"\r\n\r\neng"))
        #expect(wire.contains("name=\"diarize\"\r\n\r\ntrue"))
        #expect(wire.contains("name=\"num_speakers\"\r\n\r\n2"))
        #expect(wire.contains("name=\"tag_audio_events\"\r\n\r\ntrue"))
        #expect(wire.contains("name=\"no_verbatim\"\r\n\r\ntrue"))
        #expect(wire.components(separatedBy: "name=\"keyterms\"").count - 1 == 2)
        #expect((await recorder.finished()).contains(where: completedSession))
    }

    @Test("batch maps words audio events confidence speakers and stable IDs")
    func batchWordEventMappingAndStableIDs() async throws {
        let response = try successResponse(batchTranscript())
        let http = FakeElevenLabsHTTPTransport(responses: [response, response])
        let provider = try makeProvider(
            http: http,
            batchOptions: ElevenLabsScribeBatchOptions(speakerCount: 2)
        )
        let route = try provider.route(mode: .cloudBatch, diarizationEnabled: true)
        let context = try makeContext()
        let operationID = try #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let packet = try makePacket(operationID: operationID)
        var finals: [MeetingTranscriptionFinalEvent] = []

        for _ in 0 ..< 2 {
            let session = try await provider.makeSession(route: route, context: context)
            let recorder = ElevenLabsEventRecorder(stream: session.events)
            try await session.start()
            try await session.submit(packet)
            try await session.finish()
            finals.append(try #require((await recorder.finished()).compactMap(finalEvent).first))
        }

        #expect(finals.map(\.utterance.id) == [packet.operationID, packet.operationID])
        #expect(finals[0].utterance.words.map(\.text) == ["Hello", "(laughter)"])
        #expect(finals[0].utterance.words.map(\.speakerID) == ["speaker_0", "speaker_0"])
        #expect(finals[0].utterance.speaker?.label == "Speaker 1")
        #expect(finals[0].utterance.words[0].confidence == exp(-0.1))
        #expect(finals[0].utterance.words.map(\.id) == finals[1].utterance.words.map(\.id))
        #expect(finals[0].context.eventID == packet.operationID)
    }

    @Test("none retention disables logging without placing credentials in URLs")
    func retentionFlag() async throws {
        let http = FakeElevenLabsHTTPTransport(responses: [try successResponse(batchTranscript())])
        let provider = try makeProvider(http: http)
        let route = try provider.route(
            mode: .cloudBatch,
            diarizationEnabled: true,
            retention: .none
        )
        let session = try await provider.makeSession(route: route, context: makeContext())

        try await session.start()
        try await session.submit(makePacket())
        try await session.finish()
        let request = try #require(await http.requests().first)
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))

        #expect(request.url?.host == "api.elevenlabs.io")
        #expect(components.queryItems?.first(where: { $0.name == "enable_logging" })?.value == "false")
        #expect(components.queryItems?.contains(where: { $0.value == "test-api-key" }) == false)
    }

    @Test("webhook jobs are represented only as provider-configured accepted requests")
    func webhookJobModel() async throws {
        let response = try successResponse([
            "message": "Transcription queued",
            "request_id": "request_1",
            "transcription_id": "transcript_1",
        ])
        let http = FakeElevenLabsHTTPTransport(responses: [response])
        let transport = http
        let client = ElevenLabsScribeBatchClient(
            credentialResolver: StaticElevenLabsCredentialResolver(),
            transport: transport,
            options: try ElevenLabsScribeBatchOptions(),
            endpoint: try elevenLabsTestEndpoint().restURL(path: "/v1/speech-to-text"),
            boundary: { "KajiBoundary" }
        )
        let route = try makeProvider().route(mode: .cloudBatch)
        let result = try await client.submit(ElevenLabsScribeBatchRequest(
            route: route,
            context: makeContext(),
            packet: makePacket(),
            delivery: .configuredWebhook(webhookID: "configured_webhook", metadata: ["operation": "meeting"])
        ))
        let request = try #require(await http.requests().first)
        let wire = String(decoding: try #require(request.httpBody), as: UTF8.self)

        #expect(result == .accepted(ElevenLabsScribeBatchAcceptedJob(
            requestID: "request_1",
            transcriptionID: "transcript_1"
        )))
        #expect(wire.contains("name=\"webhook\"\r\n\r\ntrue"))
        #expect(wire.contains("name=\"webhook_id\"\r\n\r\nconfigured_webhook"))
        #expect(!wire.contains("http://"))
        #expect(!wire.contains("https://"))
    }

    @Test("realtime emits partial replacement then timestamped final with stable identity")
    func realtimePartialReplacementAndFinalization() async throws {
        let webSocket = FakeElevenLabsWebSocketTransport()
        let provider = try makeProvider(webSocket: webSocket)
        let route = try provider.route(mode: .cloudRealtime, languageCode: "eng")
        let session = try await provider.makeSession(route: route, context: makeContext(keyterms: ["Kaji"]))
        let recorder = ElevenLabsEventRecorder(stream: session.events)

        try await session.start()
        try await session.submit(makePacket())
        try #require(await webSocket.waitForSentMessageCount(1))
        await webSocket.push(.text(#"{"message_type":"partial_transcript","text":"Hello"}"#))
        await webSocket.push(.text(#"{"message_type":"partial_transcript","text":"Hello there"}"#))
        try #require(await recorder.waitForReplacement())
        let finish = Task { try await session.finish() }
        try #require(await webSocket.waitForSentMessageCount(2))
        await webSocket.push(.text(#"{"message_type":"committed_transcript","text":"Hello there"}"#))
        await webSocket.push(.text(try timestampedCommit(text: "Hello there")))
        try await finish.value
        let events = await recorder.finished()
        let partial = try #require(events.compactMap(partialEvent).first)
        let replacement = try #require(events.compactMap(replacementEvent).first)
        let final = try #require(events.compactMap(finalEvent).first)
        let request = try #require(await webSocket.request())
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))

        #expect(partial.utterance.id == replacement.utterance.id)
        #expect(replacement.utterance.id == final.utterance.id)
        #expect(partial.utterance.revision == 0)
        #expect(replacement.utterance.revision == 1)
        #expect(final.utterance.revision == 2)
        #expect(final.utterance.words.map(\.text) == ["Hello", "there"])
        #expect(final.utterance.words.map(\.speakerID) == [nil, nil])
        #expect(final.utterance.words[0].confidence == exp(-0.1))
        #expect(request.url?.scheme == "wss")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "test-api-key")
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        #expect(request.value(forHTTPHeaderField: "Pragma") == "no-cache")
        #expect(components.queryItems?.first(where: { $0.name == "include_timestamps" })?.value == "true")
        #expect(components.queryItems?.first(where: { $0.name == "audio_format" })?.value == "pcm_16000")
        #expect(components.queryItems?.filter { $0.name == "keyterms" }.map(\.value) == ["Kaji"])
    }

    @Test("realtime streams packets continuously and commits only on explicit finish")
    func realtimeCommitOrdering() async throws {
        let webSocket = FakeElevenLabsWebSocketTransport()
        let provider = try makeProvider(webSocket: webSocket)
        let session = try await provider.makeSession(
            route: provider.route(mode: .cloudRealtime),
            context: makeContext()
        )

        try await session.start()
        try await session.submit(makePacket(frameCount: 24_000))
        try #require(await webSocket.waitForSentMessageCount(2))
        var messages = try await webSocket.sentMessages().map(outboundObject)

        #expect(messages.map { $0["message_type"] as? String } == ["input_audio_chunk", "input_audio_chunk"])
        #expect(messages.map { $0["commit"] as? Bool } == [false, false])
        #expect((messages[0]["audio_base_64"] as? String)?.isEmpty == false)
        #expect((messages[1]["audio_base_64"] as? String)?.isEmpty == false)
        let finish = Task { try await session.finish() }
        try #require(await webSocket.waitForSentMessageCount(3))
        messages = try await webSocket.sentMessages().map(outboundObject)
        #expect(messages.map { $0["commit"] as? Bool } == [false, false, true])
        #expect((messages[2]["audio_base_64"] as? String)?.isEmpty == true)
        await webSocket.push(.text(#"{"message_type":"committed_transcript","text":"Ordered"}"#))
        await webSocket.push(.text(try timestampedCommit(text: "Ordered", end: 1.4)))
        try await finish.value
    }

    @Test("manual pacing commits bounded twenty-second windows without awaiting responses")
    func realtimeManualPacing() async throws {
        let webSocket = FakeElevenLabsWebSocketTransport()
        let provider = try makeProvider(webSocket: webSocket)
        let session = try await provider.makeSession(
            route: provider.route(mode: .cloudRealtime),
            context: makeContext()
        )

        try await session.start()
        try await session.submit(makePacket(frameCount: 320_000))
        try #require(await webSocket.waitForSentMessageCount(20))
        let messages = try await webSocket.sentMessages().map(outboundObject)

        #expect(messages.count == 20)
        #expect(messages.dropLast().allSatisfy { $0["commit"] as? Bool == false })
        #expect(messages.last?["commit"] as? Bool == true)
        await session.cancel()
    }

    @Test("VAD finish explicitly commits and drains the active tail")
    func realtimeVADPacing() async throws {
        let webSocket = FakeElevenLabsWebSocketTransport()
        let provider = try makeProvider(
            webSocket: webSocket,
            realtimeOptions: ElevenLabsScribeRealtimeOptions(commitStrategy: .vad)
        )
        let session = try await provider.makeSession(
            route: provider.route(mode: .cloudRealtime, retention: .none),
            context: makeContext()
        )

        try await session.start()
        let request = try #require(await webSocket.request())
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        try await session.submit(makePacket())
        let finish = Task { try await session.finish() }
        try #require(await webSocket.waitForSentMessageCount(2))
        await webSocket.push(.text(#"{"message_type":"committed_transcript","text":"VAD tail"}"#))
        await webSocket.push(.text(try timestampedCommit(text: "VAD tail")))
        try await finish.value
        let messages = try await webSocket.sentMessages().map(outboundObject)

        #expect(components.queryItems?.first(where: { $0.name == "enable_logging" })?.value == "false")
        #expect(messages.map { $0["commit"] as? Bool } == [false, true])
        #expect((messages.last?["audio_base_64"] as? String)?.isEmpty == true)
    }

    @Test("multiple pending manual commits correlate ordered results to bounded windows")
    func realtimePendingCommitCorrelation() async throws {
        let webSocket = FakeElevenLabsWebSocketTransport()
        let provider = try makeProvider(webSocket: webSocket)
        let session = try await provider.makeSession(
            route: provider.route(mode: .cloudRealtime),
            context: makeContext()
        )
        let recorder = ElevenLabsEventRecorder(stream: session.events)

        try await session.start()
        try await session.submit(makePacket(frameCount: 640_000))
        try #require(await webSocket.waitForSentMessageCount(40))
        let finish = Task { try await session.finish() }
        await webSocket.push(.text(#"{"message_type":"committed_transcript","text":"First"}"#))
        await webSocket.push(.text(try timestampedCommit(text: "First")))
        await webSocket.push(.text(#"{"message_type":"committed_transcript","text":"Second"}"#))
        await webSocket.push(.text(try timestampedCommit(text: "Second")))
        try await finish.value
        let finals = await recorder.finished().compactMap(finalEvent)

        #expect(finals.map(\.utterance.text) == ["First", "Second"])
        #expect(finals.map(\.utterance.sampleRange.startFrame) == [0, 320_000])
        #expect(finals.map(\.utterance.sampleRange.endFrame) == [320_000, 640_000])
        #expect(Set(finals.map(\.utterance.id)).count == 2)
    }

    @Test("manual commit backlog is bounded")
    func realtimePendingCommitBound() async throws {
        let webSocket = FakeElevenLabsWebSocketTransport()
        let provider = try makeProvider(
            webSocket: webSocket,
            realtimeOptions: ElevenLabsScribeRealtimeOptions(manualCommitWindowSeconds: 10)
        )
        let session = try await provider.makeSession(
            route: provider.route(mode: .cloudRealtime),
            context: makeContext()
        )

        try await session.start()
        await #expect(throws: ElevenLabsScribeError.providerFailure(
            code: "commit-backlog-full",
            classification: .transient,
            retryAfterMilliseconds: nil
        )) {
            try await session.submit(makePacket(frameCount: 1_440_000))
        }

        #expect(await webSocket.wasCancelled())
        #expect(await webSocket.sentMessages().count < 90)
    }

    @Test("empty silence commits and nullable words finalize without cancelling")
    func realtimeNullableWordsAndSilence() async throws {
        for (text, wordsJSON, expectedFinalCount) in [
            ("", "null", 0),
            ("Transcript", "null", 1),
            ("Transcript", nil, 1),
        ] as [(String, String?, Int)] {
            let webSocket = FakeElevenLabsWebSocketTransport()
            let provider = try makeProvider(webSocket: webSocket)
            let session = try await provider.makeSession(
                route: provider.route(mode: .cloudRealtime),
                context: makeContext()
            )
            let recorder = ElevenLabsEventRecorder(stream: session.events)

            try await session.start()
            try await session.submit(makePacket())
            let finish = Task { try await session.finish() }
            try #require(await webSocket.waitForSentMessageCount(2))
            await webSocket.push(.text("{\"message_type\":\"committed_transcript\",\"text\":\"\(text)\"}"))
            let words = wordsJSON.map { ",\"words\":\($0)" } ?? ""
            await webSocket.push(.text(
                "{\"message_type\":\"committed_transcript_with_timestamps\",\"text\":\"\(text)\"\(words)}"
            ))
            try await finish.value
            let events = await recorder.finished()

            #expect(events.compactMap(finalEvent).count == expectedFinalCount)
            #expect(!events.contains { if case .failure = $0 { true } else { false } })
        }
    }

    @Test("JSON booleans are rejected as numeric transcription fields")
    func booleanNumericFields() async throws {
        var transcript = batchTranscript()
        transcript["language_probability"] = true
        transcript["words"] = NSNull()
        let http = FakeElevenLabsHTTPTransport(responses: [try successResponse(transcript)])
        let provider = try makeProvider(http: http)
        let session = try await provider.makeSession(
            route: provider.route(mode: .cloudBatch),
            context: makeContext()
        )

        try await session.start()
        await #expect(throws: ElevenLabsScribeError.malformedResponse) {
            try await session.submit(makePacket())
        }
        await session.cancel()
    }

    @Test("malformed packets and provider frames fail with bounded generic errors")
    func malformedInput() async throws {
        let provider = try makeProvider()
        let batch = try await provider.makeSession(
            route: provider.route(mode: .cloudBatch),
            context: makeContext()
        )
        try await batch.start()
        await #expect(throws: ElevenLabsScribeError.self) {
            try await batch.submit(makePacket(sampleRate: 8000, frameCount: 1600))
        }
        await batch.cancel()

        let webSocket = FakeElevenLabsWebSocketTransport()
        let realtimeProvider = try makeProvider(webSocket: webSocket)
        let realtime = try await realtimeProvider.makeSession(
            route: realtimeProvider.route(mode: .cloudRealtime),
            context: makeContext()
        )
        let recorder = ElevenLabsEventRecorder(stream: realtime.events)
        try await realtime.start()
        await webSocket.push(.binary(Data([0, 1])))
        let failure = try #require((await recorder.finished()).compactMap(failureEvent).first)

        #expect(failure.classification == .invalidRequest)
        #expect(failure.message == "ElevenLabs rejected the transcription input.")
        #expect(await webSocket.wasCancelled())
    }

    @Test("HTTP authentication and rate failures are classified without upstream details")
    func httpErrorClassifications() async throws {
        let auth = try failureResponse(status: 401, code: "invalid_api_key", retryAfter: nil)
        let rate = try failureResponse(status: 429, code: "rate_limit_exceeded", retryAfter: "2")
        let http = FakeElevenLabsHTTPTransport(responses: [auth, rate])
        let provider = try makeProvider(http: http)
        var failures: [MeetingTranscriptionFailureEvent] = []
        var rateEvents: [MeetingTranscriptionRateLimitEvent] = []

        for _ in 0 ..< 2 {
            let session = try await provider.makeSession(
                route: provider.route(mode: .cloudBatch),
                context: makeContext()
            )
            let recorder = ElevenLabsEventRecorder(stream: session.events)
            try await session.start()
            await #expect(throws: ElevenLabsScribeError.self) {
                try await session.submit(makePacket())
            }
            try await session.finish()
            let events = await recorder.finished()
            failures.append(try #require(events.compactMap(failureEvent).first))
            rateEvents.append(contentsOf: events.compactMap(rateLimitEvent))
        }

        #expect(failures.map(\.classification) == [.authentication, .rateLimited])
        #expect(failures.map(\.code) == ["invalid-api-key", "rate-limit-exceeded"])
        #expect(failures.allSatisfy { !$0.message.contains("sensitive") })
        #expect(rateEvents.first?.retryAfterMilliseconds == 2000)
    }

    @Test("realtime auth and rate events are classified")
    func realtimeErrorClassifications() async throws {
        for (messageType, classification) in [
            ("auth_error", MeetingTranscriptionFailureClassification.authentication),
            ("rate_limited", MeetingTranscriptionFailureClassification.rateLimited),
        ] {
            let webSocket = FakeElevenLabsWebSocketTransport()
            let provider = try makeProvider(webSocket: webSocket)
            let session = try await provider.makeSession(
                route: provider.route(mode: .cloudRealtime),
                context: makeContext()
            )
            let recorder = ElevenLabsEventRecorder(stream: session.events)
            try await session.start()
            await webSocket.push(.text("{\"message_type\":\"\(messageType)\",\"error\":\"sensitive key detail\"}"))
            let failure = try #require((await recorder.finished()).compactMap(failureEvent).first)

            #expect(failure.classification == classification)
            #expect(!failure.message.contains("sensitive"))
        }
    }

    @Test("cancellation tears down both transports and emits cancelled state")
    func cancellation() async throws {
        let http = FakeElevenLabsHTTPTransport()
        let webSocket = FakeElevenLabsWebSocketTransport()
        let provider = try makeProvider(http: http, webSocket: webSocket)
        let batch = try await provider.makeSession(
            route: provider.route(mode: .cloudBatch),
            context: makeContext()
        )
        let batchRecorder = ElevenLabsEventRecorder(stream: batch.events)
        try await batch.start()
        await batch.cancel()

        let realtime = try await provider.makeSession(
            route: provider.route(mode: .cloudRealtime),
            context: makeContext()
        )
        let realtimeRecorder = ElevenLabsEventRecorder(stream: realtime.events)
        try await realtime.start()
        await realtime.cancel()

        #expect(await http.wasCancelled())
        #expect(await webSocket.wasCancelled())
        #expect((await batchRecorder.finished()).contains(where: cancelledSession))
        #expect((await realtimeRecorder.finished()).contains(where: cancelledSession))
    }
}

private struct StaticElevenLabsCredentialResolver: ElevenLabsScribeCredentialResolving {
    let value: Data

    init(_ value: String = "test-api-key") {
        self.value = Data(value.utf8)
    }

    func resolveAPIKey() async throws -> Data { value }
}

private struct FakeElevenLabsHTTPTransportFactory: ElevenLabsScribeHTTPTransportFactory {
    let transport: FakeElevenLabsHTTPTransport

    func makeTransport() -> any ElevenLabsScribeHTTPTransporting { transport }
}

private actor FakeElevenLabsHTTPTransport: ElevenLabsScribeHTTPTransporting {
    private var queuedResponses: [ElevenLabsScribeHTTPResponse]
    private var recordedRequests: [URLRequest] = []
    private var cancelled = false

    init(responses: [ElevenLabsScribeHTTPResponse] = []) {
        queuedResponses = responses
    }

    func execute(_ request: URLRequest, maximumResponseBytes: Int) throws -> ElevenLabsScribeHTTPResponse {
        guard !cancelled, !queuedResponses.isEmpty else {
            throw ElevenLabsScribeError.providerFailure(
                code: cancelled ? "cancelled" : "missing-fake-response",
                classification: cancelled ? .cancelled : .permanent,
                retryAfterMilliseconds: nil
            )
        }
        recordedRequests.append(request)
        let response = queuedResponses.removeFirst()
        guard response.body.count <= maximumResponseBytes else { throw ElevenLabsScribeError.responseTooLarge }
        return response
    }

    func cancel() { cancelled = true }
    func requests() -> [URLRequest] { recordedRequests }
    func wasCancelled() -> Bool { cancelled }
}

private struct FakeElevenLabsWebSocketTransportFactory: STTWebSocketTransportFactory {
    let transport: FakeElevenLabsWebSocketTransport

    func makeTransport() -> any STTWebSocketTransporting { transport }
}

private actor FakeElevenLabsWebSocketTransport: STTWebSocketTransporting {
    private let stream: AsyncStream<STTWebSocketEvent>
    private let continuation: AsyncStream<STTWebSocketEvent>.Continuation
    private var connectedRequest: URLRequest?
    private var messages: [STTWebSocketMessage] = []
    private var state = STTWebSocketState.disconnected
    private var cancelled = false

    init() {
        let pair = AsyncStream<STTWebSocketEvent>.makeStream(bufferingPolicy: .unbounded)
        stream = pair.stream
        continuation = pair.continuation
    }

    func events() -> AsyncStream<STTWebSocketEvent> { stream }
    func currentState() -> STTWebSocketState { state }

    func connect(request: URLRequest) throws {
        connectedRequest = request
        state = .open
        continuation.yield(.stateChanged(.connecting))
        continuation.yield(.stateChanged(.open))
        continuation.yield(.message(.text(try sessionStarted(request))))
    }

    func send(_ message: STTWebSocketMessage) { messages.append(message) }
    func ping() { continuation.yield(.pong) }

    func close(code: Int, reason _: String?) {
        state = .disconnected
        continuation.yield(.closed(code: code))
        continuation.finish()
    }

    func cancel() {
        cancelled = true
        state = .disconnected
        continuation.yield(.closed(code: 1001))
        continuation.finish()
    }

    func push(_ message: STTWebSocketMessage) { continuation.yield(.message(message)) }
    func request() -> URLRequest? { connectedRequest }
    func sentMessages() -> [STTWebSocketMessage] { messages }
    func wasCancelled() -> Bool { cancelled }

    func waitForSentMessageCount(_ count: Int) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while messages.count < count, clock.now < deadline {
            try? await clock.sleep(for: .milliseconds(10))
        }
        return messages.count >= count
    }

    private func sessionStarted(_ request: URLRequest) throws -> String {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        func value(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }
        var config: [String: Any] = [
            "sample_rate": 16_000,
            "audio_format": value("audio_format") ?? "",
            "commit_strategy": value("commit_strategy") ?? "",
            "model_id": value("model_id") ?? "",
            "enable_logging": value("enable_logging") == "true",
            "include_timestamps": value("include_timestamps") == "true",
            "include_language_detection": value("include_language_detection") == "true",
            "no_verbatim": value("no_verbatim") == "true",
            "vad_silence_threshold_secs": Double(value("vad_silence_threshold_secs") ?? "") ?? -1,
            "vad_threshold": Double(value("vad_threshold") ?? "") ?? -1,
            "min_speech_duration_ms": Int(value("min_speech_duration_ms") ?? "") ?? -1,
            "min_silence_duration_ms": Int(value("min_silence_duration_ms") ?? "") ?? -1,
            "keyterms": queryItems.filter { $0.name == "keyterms" }.compactMap(\.value),
        ]
        if let languageCode = value("language_code") { config["language_code"] = languageCode }
        let object: [String: Any] = [
            "message_type": "session_started",
            "session_id": "session_1",
            "config": config,
        ]
        return try #require(String(data: JSONSerialization.data(withJSONObject: object), encoding: .utf8))
    }
}

private actor ElevenLabsEventRecorder {
    private var events: [MeetingTranscriptionProviderEvent] = []
    private var complete = false

    init(stream: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>) {
        Task { [weak self] in
            await self?.collect(stream)
        }
    }

    private func collect(_ stream: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>) async {
        do {
            for try await event in stream { events.append(event) }
        } catch {}
        complete = true
    }

    func finished() async -> [MeetingTranscriptionProviderEvent] {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !complete, clock.now < deadline {
            try? await clock.sleep(for: .milliseconds(10))
        }
        return events
    }

    func waitForReplacement() async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !events.contains(where: { if case .replacement = $0 { true } else { false } }), clock.now < deadline {
            try? await clock.sleep(for: .milliseconds(10))
        }
        return events.contains { if case .replacement = $0 { true } else { false } }
    }
}

private func makeProvider(
    http: FakeElevenLabsHTTPTransport = FakeElevenLabsHTTPTransport(),
    webSocket: FakeElevenLabsWebSocketTransport = FakeElevenLabsWebSocketTransport(),
    batchOptions: ElevenLabsScribeBatchOptions? = nil,
    realtimeOptions: ElevenLabsScribeRealtimeOptions? = nil
) throws -> ElevenLabsScribeMeetingTranscriptionProvider {
    try ElevenLabsScribeMeetingTranscriptionProvider(
        credentialResolver: StaticElevenLabsCredentialResolver(),
        httpTransportFactory: FakeElevenLabsHTTPTransportFactory(transport: http),
        webSocketTransportFactory: FakeElevenLabsWebSocketTransportFactory(transport: webSocket),
        batchOptions: batchOptions ?? ElevenLabsScribeBatchOptions(),
        realtimeOptions: realtimeOptions ?? ElevenLabsScribeRealtimeOptions(),
        endpoint: elevenLabsTestEndpoint(),
        model: try elevenLabsTestModels()[0],
        models: elevenLabsTestModels(),
        mode: .cloudBatch,
        nowMilliseconds: { 10_000 },
        boundary: { "KajiBoundary" }
    )
}

private func makeContext(keyterms: [String] = []) throws -> MeetingTrackTranscriptionContextSnapshot {
    try MeetingTrackTranscriptionContextSnapshot(
        sessionID: MeetingTranscriptionCoreFixtures.sessionID,
        trackID: MeetingTranscriptionCoreFixtures.trackID,
        source: .microphone,
        canonicalSampleRateHertz: 16_000,
        channelCount: 1,
        startedAtMilliseconds: 1_000,
        keyterms: keyterms
    )
}

private func makePacket(
    operationID: UUID = UUID(),
    sampleRate: Int = 16_000,
    frameCount: Int = 16_000
) throws -> MeetingNormalizedAudioPacket {
    try MeetingNormalizedAudioPacket(
        operationID: operationID,
        sessionID: MeetingTranscriptionCoreFixtures.sessionID,
        trackID: MeetingTranscriptionCoreFixtures.trackID,
        source: .microphone,
        sampleRange: MeetingCanonicalSampleRange(
            startFrame: 0,
            endFrame: Int64(frameCount),
            sampleRateHertz: sampleRate
        ),
        encoding: .pcmSigned16LittleEndian,
        sampleRateHertz: sampleRate,
        channelCount: 1,
        bytes: Data(repeating: 1, count: frameCount * 2),
        providerEpoch: .initial
    )
}

private func batchTranscript() -> [String: Any] {
    [
        "language_code": "eng",
        "language_probability": 0.98,
        "text": "Hello (laughter)",
        "words": [
            [
                "text": "Hello", "start": 0.0, "end": 0.2, "type": "word",
                "speaker_id": "speaker_0", "logprob": -0.1,
            ],
            [
                "text": " ", "start": 0.2, "end": 0.2, "type": "spacing",
                "speaker_id": "speaker_0", "logprob": 0.0,
            ],
            [
                "text": "(laughter)", "start": 0.2, "end": 0.3, "type": "audio_event",
                "speaker_id": "speaker_0", "logprob": -0.2,
            ],
        ],
        "transcription_id": "transcript_1",
        "audio_duration_secs": 1.0,
    ]
}

private func timestampedCommit(text: String, end: Double = 0.8) throws -> String {
    let object: [String: Any] = [
        "message_type": "committed_transcript_with_timestamps",
        "text": text,
        "language_code": "eng",
        "words": [
            ["text": "Hello", "start": 0.0, "end": min(0.3, end), "type": "word", "logprob": -0.1],
            ["text": " ", "start": min(0.3, end), "end": min(0.4, end), "type": "spacing", "logprob": 0.0],
            ["text": text == "Ordered" ? "Ordered" : "there", "start": min(0.4, end), "end": end, "type": "word", "logprob": -0.2],
        ],
    ]
    return try #require(String(data: JSONSerialization.data(withJSONObject: object), encoding: .utf8))
}

private func outboundObject(_ message: STTWebSocketMessage) throws -> [String: Any] {
    guard case let .text(value) = message,
          let data = value.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        throw ElevenLabsScribeError.malformedResponse
    }
    return object
}

private func successResponse(_ object: [String: Any]) throws -> ElevenLabsScribeHTTPResponse {
    try ElevenLabsScribeHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: JSONSerialization.data(withJSONObject: object)
    )
}

private func failureResponse(
    status: Int,
    code: String,
    retryAfter: String?
) throws -> ElevenLabsScribeHTTPResponse {
    var headers = ["Content-Type": "application/json"]
    if let retryAfter { headers["Retry-After"] = retryAfter }
    return try ElevenLabsScribeHTTPResponse(
        statusCode: status,
        headers: headers,
        body: JSONSerialization.data(withJSONObject: [
            "detail": ["code": code, "message": "sensitive upstream detail"],
        ])
    )
}

private func partialEvent(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionPartialEvent? {
    guard case let .partial(value) = event else { return nil }
    return value
}

private func replacementEvent(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionReplacementEvent? {
    guard case let .replacement(value) = event else { return nil }
    return value
}

private func finalEvent(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionFinalEvent? {
    guard case let .final(value) = event else { return nil }
    return value
}

private func failureEvent(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionFailureEvent? {
    guard case let .failure(value) = event else { return nil }
    return value
}

private func rateLimitEvent(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionRateLimitEvent? {
    guard case let .rateLimit(value) = event else { return nil }
    return value
}

private func completedSession(_ event: MeetingTranscriptionProviderEvent) -> Bool {
    guard case let .session(value) = event else { return false }
    return value.state == .completed
}

private func cancelledSession(_ event: MeetingTranscriptionProviderEvent) -> Bool {
    guard case let .session(value) = event else { return false }
    return value.state == .cancelled
}
