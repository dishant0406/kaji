import Foundation
import Testing

@testable import Kaji
private enum AssemblyAITestModel {
    static let id = "universal-3-5-pro"
}

private enum AssemblyAIStreamingRegion: String, CaseIterable {
    case global
    case us
    case eu

    var endpointString: String {
        switch self {
        case .global: "wss://streaming.assemblyai.com"
        case .us: "wss://streaming.us.assemblyai.com"
        case .eu: "wss://streaming.eu.assemblyai.com"
        }
    }
}

private func assemblyTestEndpoint(
    region: AssemblyAIStreamingRegion = .global
) throws -> MeetingTranscriptionEndpointSnapshot {
    try MeetingTranscriptionEndpointProfile(
        providerID: AssemblyAIMeetingTranscriptionProvider.providerID,
        displayName: region.rawValue,
        variant: .assemblyAIStreamingV3,
        regionID: region.rawValue,
        restBaseURL: nil,
        webSocketBaseURL: region.endpointString,
        discovery: MeetingTranscriptionModelDiscoveryConfiguration(kind: .manual),
        source: .builtIn
    ).snapshot
}

private func assemblyTestModel() throws -> MeetingDiscoveredTranscriptionModel {
    try MeetingDiscoveredTranscriptionModel(
        id: AssemblyAITestModel.id,
        displayName: "Test Model",
        modes: [.cloudRealtime],
        languageCodes: ["en", "es"],
        capabilityConfidence: .manual
    )
}


@Suite("AssemblyAI meeting transcription provider")
struct AssemblyAIMeetingTranscriptionProviderTests {
    @Test("capabilities describe all streaming models regions privacy and duration")
    func capabilities() throws {
        let provider = try makeProvider(transport: FakeAssemblyAIWebSocketTransport())

        #expect(provider.descriptor.models.map(\.id) == [AssemblyAITestModel.id])
        for model in provider.descriptor.models {
            #expect(model.capabilities.modes == [.cloudRealtime])
            #expect(model.capabilities.inputFormats.first?.encoding == .pcmSigned16LittleEndian)
            #expect(model.capabilities.inputFormats.first?.sampleRatesHertz == [16_000])
            #expect(model.capabilities.inputFormats.first?.channelCounts == [1])
            #expect(model.capabilities.partialResults.availability == .supported)
            #expect(model.capabilities.timing.availability == .supported)
            #expect(model.capabilities.confidence.availability == .supported)
            #expect(model.capabilities.sessionDuration.maximumSeconds == 10_800)
            #expect(model.regions.map(\.id) == ["global"])
            #expect(model.privacy.supportedRetention == [.none, .providerDefault])
        }
    }

    @Test("speaker bounds and retention claims are enforced")
    func configurationBounds() throws {
        #expect(throws: AssemblyAIMeetingTranscriptionError.invalidConfiguration) {
            try AssemblyAIStreamingSessionConfiguration(maximumSpeakers: 0)
        }
        #expect(throws: AssemblyAIMeetingTranscriptionError.invalidConfiguration) {
            try AssemblyAIStreamingSessionConfiguration(maximumSpeakers: 11)
        }
        _ = try AssemblyAIStreamingSessionConfiguration(maximumSpeakers: 1)
        _ = try AssemblyAIStreamingSessionConfiguration(maximumSpeakers: 10)

        let provider = try makeProvider(transport: FakeAssemblyAIWebSocketTransport())
        #expect(throws: AssemblyAIMeetingTranscriptionError.invalidRoute) {
            try provider.route(retention: .none)
        }
        let privateProvider = try makeProvider(
            transport: FakeAssemblyAIWebSocketTransport(),
            configuration: AssemblyAIStreamingSessionConfiguration(
                privacy: AssemblyAIAccountPrivacyConfiguration(trainingOptOutAttested: true)
            )
        )
        _ = try privateProvider.route(retention: .none)
        #expect(throws: AssemblyAIMeetingTranscriptionError.invalidRoute) {
            try privateProvider.route(retention: .configurable)
        }
    }

    @Test("API keys use headers and exact regional endpoints")
    func apiKeyRequests() async throws {
        for region in AssemblyAIStreamingRegion.allCases {
            let transport = FakeAssemblyAIWebSocketTransport(connectMessages: [beginMessage(speakerLabels: true)])
            let provider = try makeProvider(transport: transport, region: region)
            let route = try provider.route(
                languageCodes: ["en", "es"],
                diarizationEnabled: true
            )
            let context = try makeContext(keyterms: ["AssemblyAI", "Kaji"])
            let session = try await provider.makeSession(route: route, context: context)

            try await session.start()
            let request = try #require(await transport.request())
            let requestURL = try #require(request.url)
            let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

            #expect(request.url?.scheme == "wss")
            #expect(request.url?.host == URL(string: region.endpointString)?.host)
            #expect(request.url?.path == "/v3/ws")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "api-key-value")
            #expect(query["token"] == nil)
            #expect(query["speech_model"] == "universal-3-5-pro")
            #expect(query["encoding"] == "pcm_s16le")
            #expect(query["sample_rate"] == "16000")
            #expect(query["language_codes"] == "[\"en\",\"es\"]")
            #expect(query["keyterms_prompt"] == "[\"AssemblyAI\",\"Kaji\"]")
            #expect(query["speaker_labels"] == "true")
            await session.cancel()
        }
    }

    @Test("temporary tokens use the documented one-time query credential")
    func temporaryTokenRequest() async throws {
        let transport = FakeAssemblyAIWebSocketTransport(connectMessages: [beginMessage()])
        let resolver = AssemblyAISecretResolver {
            try AssemblyAIStreamingCredential(temporaryToken: "temporary-token-value")
        }
        let provider = try AssemblyAIMeetingTranscriptionProvider(
            secretResolver: resolver,
            transportFactory: FakeAssemblyAIWebSocketTransportFactory(transport: transport),
            configuration: AssemblyAIStreamingSessionConfiguration(),
            endpoint: assemblyTestEndpoint(),
            model: assemblyTestModel()
        )
        let session = try await provider.makeSession(route: provider.route(), context: makeContext())

        try await session.start()
        let request = try #require(await transport.request())
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(components.queryItems?.first(where: { $0.name == "token" })?.value == "temporary-token-value")
        await session.cancel()
    }

    @Test("partial and final turns preserve stable identity words confidence and mid-turn speakers")
    func partialAndFinalTurns() async throws {
        let transport = FakeAssemblyAIWebSocketTransport(connectMessages: [beginMessage(speakerLabels: true)])
        let provider = try makeProvider(transport: transport)
        let session = try await concreteSession(
            provider: provider,
            route: provider.route(diarizationEnabled: true)
        )
        let recorder = AssemblyAIEventRecorder(stream: session.events)

        try await session.start()
        try #require(await recorder.waitForSession(.ready))
        let packet = try makePacket(frameCount: 1600)
        try await session.submit(packet)
        await transport.push(.text(turnMessage(
            order: 0,
            transcript: "Hello",
            final: false,
            formatted: false,
            speaker: "A",
            words: [word("Hello", start: 0, end: 40, confidence: 0.8)]
        )))
        await transport.push(.text(turnMessage(
            order: 0,
            transcript: "Hello there.",
            final: true,
            formatted: true,
            speaker: "A",
            words: [
                word("Hello", start: 0, end: 40, confidence: 0.8, speaker: "A"),
                word("there.", start: 40, end: 90, confidence: 0.9, speaker: "B"),
            ]
        )))
        try #require(await recorder.waitForEventCount(4))
        let events = await recorder.snapshot()
        let partial = try #require(events.compactMap(partialEvent).first)
        let final = try #require(events.compactMap(finalEvent).first)

        #expect(partial.utterance.id == final.utterance.id)
        #expect(partial.utterance.revision == 0)
        #expect(final.utterance.revision == 1)
        #expect(final.context.operationID == packet.operationID)
        #expect(final.utterance.sampleRange.startFrame == 0)
        #expect(final.utterance.sampleRange.endFrame == 1440)
        #expect(final.utterance.words.map(\.confidence) == [0.8, 0.9])
        #expect(final.utterance.words.map(\.speakerID) == ["A", "B"])
        #expect(final.utterance.speaker?.label == "Speaker A")
        await session.cancel()
    }

    @Test("UNKNOWN speakers and unsolicited configuration acknowledgements are safely ignored")
    func unknownSpeakerAndConfigurationUpdates() async throws {
        let transport = FakeAssemblyAIWebSocketTransport(connectMessages: [beginMessage(speakerLabels: true)])
        let provider = try makeProvider(transport: transport)
        let session = try await concreteSession(provider: provider, route: provider.route(diarizationEnabled: true))
        let recorder = AssemblyAIEventRecorder(stream: session.events)

        try await session.start()
        try #require(await recorder.waitForSession(.ready))
        try await session.submit(makePacket(frameCount: 800))
        try await session.updateConfiguration(AssemblyAIStreamingConfigurationUpdate(
            prompt: "A product planning meeting",
            keyterms: ["Muxy"],
            languageCodes: ["en"]
        ))
        await transport.push(.text("{\"type\":\"UpdateConfiguration\",\"mode\":\"balanced\"}"))
        await transport.push(.text(turnMessage(
            order: 0,
            transcript: "Yeah.",
            final: true,
            formatted: true,
            speaker: "UNKNOWN",
            words: [word("Yeah.", start: 0, end: 40, confidence: 0.6, speaker: "UNKNOWN")]
        )))
        try #require(await recorder.waitForFinalCount(1))
        let events = await recorder.snapshot()
        let final = try #require(events.compactMap(finalEvent).first)
        let outbound = await transport.sentMessages()

        #expect(final.utterance.speaker?.id == "UNKNOWN")
        #expect(final.utterance.speaker?.label == "UNKNOWN")
        #expect(final.utterance.words.first?.speakerID == "UNKNOWN")
        #expect(!events.contains { if case .failure = $0 { true } else { false } })
        #expect(outbound.contains(where: configurationUpdateMessage))
        await session.cancel()
    }

    @Test("stream timestamps rebase across nonzero origins gaps replay and rotated epochs")
    func streamTimestampMapping() async throws {
        let transport = FakeAssemblyAIWebSocketTransport(connectMessages: [beginMessage()])
        let provider = try makeProvider(transport: transport)
        let session = try await concreteSession(provider: provider, route: provider.route())
        let recorder = AssemblyAIEventRecorder(stream: session.events)
        let replayEpoch = try #require(MeetingProviderEpoch(rawValue: 1))
        let rotatedEpoch = try #require(MeetingProviderEpoch(rawValue: 2))
        let replayOperation = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let rotatedOperation = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!

        try await session.start()
        try #require(await recorder.waitForSession(.ready))
        try await session.submit(makePacket(
            frameCount: 800,
            startFrame: 32_000,
            operationID: replayOperation,
            providerEpoch: replayEpoch,
            isReplay: true
        ))
        try await session.submit(makePacket(
            frameCount: 800,
            startFrame: 40_000,
            operationID: rotatedOperation,
            providerEpoch: rotatedEpoch
        ))
        await transport.push(.text(turnMessage(
            order: 0,
            transcript: "Replay.",
            final: true,
            formatted: true,
            words: [word("Replay.", start: 0, end: 40, confidence: 0.9)]
        )))
        await transport.push(.text(turnMessage(
            order: 1,
            transcript: "Rotated.",
            final: true,
            formatted: true,
            words: [word("Rotated.", start: 60, end: 90, confidence: 0.9)]
        )))
        try #require(await recorder.waitForFinalCount(2))
        let finals = await recorder.snapshot().compactMap(finalEvent)

        #expect(finals.map(\.context.operationID) == [replayOperation, rotatedOperation])
        #expect(finals.map(\.context.providerEpoch) == [replayEpoch, rotatedEpoch])
        #expect(finals.map(\.utterance.sampleRange.startFrame) == [32_000, 40_160])
        #expect(finals.map(\.utterance.sampleRange.endFrame) == [32_640, 40_640])
        await session.cancel()
    }

    @Test("speaker revisions amend committed metadata without changing text or timing")
    func speakerRevisionStrategy() async throws {
        let revision = """
        {"type":"SpeakerRevision","revisions":[{"turn_order":0,"speaker_label":"B","words":[{"text":"Hello","speaker":"B","start":0,"end":40},{"text":"there.","speaker":"UNKNOWN","start":40,"end":90}]}]}
        """
        let transport = FakeAssemblyAIWebSocketTransport(
            connectMessages: [beginMessage(speakerLabels: true)],
            terminationMessages: [revision, terminationMessage()]
        )
        let provider = try makeProvider(transport: transport)
        let session = try await concreteSession(provider: provider, route: provider.route(diarizationEnabled: true))
        let recorder = AssemblyAIEventRecorder(stream: session.events)

        try await session.start()
        try #require(await recorder.waitForSession(.ready))
        try await session.submit(makePacket(frameCount: 1600))
        try await session.submit(makePacket(frameCount: 400, startFrame: 1600))
        await transport.push(.text(turnMessage(
            order: 0,
            transcript: "Hello there.",
            final: true,
            formatted: true,
            speaker: "A",
            words: [
                word("Hello", start: 0, end: 40, confidence: 0.8, speaker: "A"),
                word("there.", start: 40, end: 90, confidence: 0.9, speaker: "A"),
            ]
        )))
        try #require(await recorder.waitForFinalCount(1))
        try await session.finish()
        let events = await recorder.finishedSnapshot()
        let final = try #require(events.compactMap(finalEvent).first)
        let amendment = try #require(events.compactMap(metadataAmendmentEvent).first)

        #expect(amendment.utteranceID == final.utterance.id)
        #expect(amendment.words.map(\.sampleRange) == final.utterance.words.map(\.sampleRange))
        #expect(amendment.speaker?.id == "B")
        #expect(amendment.words.map(\.speakerID) == ["B", "UNKNOWN"])
        #expect(await transport.sentMessages().compactMap { message -> Int? in
            guard case let .binary(data) = message else { return nil }
            return data.count
        } == [3200, 1600])

        var reducer = try MeetingTranscriptRevisionReducer()
        #expect(try reducer.apply(.final(final)) == .applied)
        #expect(try reducer.apply(.metadataAmendment(amendment)) == .applied)
        #expect(reducer.ledger.record(id: final.utterance.id)?.current.text == "Hello there.")
        #expect(reducer.ledger.record(id: final.utterance.id)?.current.sampleRange == final.utterance.sampleRange)
        #expect(reducer.ledger.record(id: final.utterance.id)?.current.speaker?.id == "B")
    }

    @Test("duplicate and unknown out-of-order turns are ignored")
    func duplicateAndOutOfOrderTurns() async throws {
        let transport = FakeAssemblyAIWebSocketTransport(connectMessages: [beginMessage()])
        let provider = try makeProvider(transport: transport)
        let session = try await concreteSession(provider: provider, route: provider.route())
        let recorder = AssemblyAIEventRecorder(stream: session.events)
        let turn = turnMessage(
            order: 1,
            transcript: "First.",
            final: true,
            formatted: true,
            words: [word("First.", start: 0, end: 40, confidence: 0.9)]
        )

        try await session.start()
        try #require(await recorder.waitForSession(.ready))
        try await session.submit(makePacket(frameCount: 800))
        await transport.push(.text(turn))
        await transport.push(.text(turn))
        await transport.push(.text(turnMessage(
            order: 0,
            transcript: "Late.",
            final: true,
            formatted: true,
            words: [word("Late.", start: 0, end: 40, confidence: 0.9)]
        )))
        try #require(await recorder.waitForEventCount(4))
        let events = await recorder.snapshot()

        #expect(events.compactMap(finalEvent).count == 1)
        #expect(events.contains(where: outOfOrderWarning))
        await session.cancel()
    }

    @Test("malformed and oversized provider frames fail generically", arguments: [false, true])
    func invalidFrames(oversized: Bool) async throws {
        let transport = FakeAssemblyAIWebSocketTransport(connectMessages: [beginMessage()])
        let configuration = try AssemblyAIStreamingSessionConfiguration(maximumInboundFrameBytes: 1024)
        let provider = try makeProvider(transport: transport, configuration: configuration)
        let session = try await concreteSession(provider: provider, route: provider.route())
        let recorder = AssemblyAIEventRecorder(stream: session.events)

        try await session.start()
        try #require(await recorder.waitForSession(.ready))
        let frame = oversized ? String(repeating: "x", count: 1025) : "{\"type\":\"Turn\",\"unexpected\":true}"
        await transport.push(.text(frame))
        let events = await recorder.finishedSnapshot()
        let failure = try #require(events.compactMap(failureEvent).first)

        #expect(failure.message == "AssemblyAI streaming transcription could not continue.")
        #expect(failure.classification == .invalidRequest)
        #expect(failure.code == (oversized ? "response-too-large" : "malformed-provider-response"))
        #expect(await transport.wasCancelled())
    }

    @Test("authentication and rate-limit errors are classified", arguments: [401, 429])
    func serviceFailures(code: Int) async throws {
        let transport = FakeAssemblyAIWebSocketTransport(connectMessages: [beginMessage()])
        let provider = try makeProvider(transport: transport)
        let session = try await concreteSession(provider: provider, route: provider.route())
        let recorder = AssemblyAIEventRecorder(stream: session.events)

        try await session.start()
        try #require(await recorder.waitForSession(.ready))
        await transport.push(.text("{\"type\":\"Error\",\"error_code\":\(code),\"error\":\"sensitive upstream detail\"}"))
        let events = await recorder.finishedSnapshot()
        let failure = try #require(events.compactMap(failureEvent).first)

        #expect(failure.classification == (code == 401 ? .authentication : .rateLimited))
        #expect(failure.code == (code == 401 ? "authentication-failed" : "rate-limited"))
        #expect(!failure.message.contains("sensitive"))
    }

    @Test("three-hour expiry schedules a rotation warning")
    func rotationWarning() async throws {
        let transport = FakeAssemblyAIWebSocketTransport(connectMessages: [beginMessage(expiresAt: 10_800)])
        let provider = try makeProvider(
            transport: transport,
            nowMilliseconds: { 0 },
            sleep: { _ in }
        )
        let session = try await concreteSession(provider: provider, route: provider.route())
        let recorder = AssemblyAIEventRecorder(stream: session.events)

        try await session.start()
        try #require(await recorder.waitForWarning(code: "session-rotation-required"))
        #expect(provider.descriptor.models.first?.capabilities.sessionDuration.maximumSeconds == 10_800)
        await session.cancel()
    }

    @Test("audio chunks enforce 50 to 1000 milliseconds and finish drains termination")
    func audioBoundsAndFinish() async throws {
        let transport = FakeAssemblyAIWebSocketTransport(
            connectMessages: [beginMessage()],
            terminationMessages: [terminationMessage(audio: 1, session: 2)]
        )
        let provider = try makeProvider(transport: transport)
        let session = try await concreteSession(provider: provider, route: provider.route())
        let recorder = AssemblyAIEventRecorder(stream: session.events)

        try await session.start()
        try #require(await recorder.waitForSession(.ready))
        try await session.submit(makePacket(frameCount: 799))
        await #expect(throws: AssemblyAIMeetingTranscriptionError.invalidPacket) {
            try await session.submit(makePacket(frameCount: 16_001))
        }
        try await session.submit(makePacket(frameCount: 800))
        try await session.submit(makePacket(frameCount: 16_000, startFrame: 800))
        try await session.finish()
        let events = await recorder.finishedSnapshot()
        let binarySizes = await transport.sentMessages().compactMap { message -> Int? in
            guard case let .binary(data) = message else { return nil }
            return data.count
        }

        #expect(binarySizes == [3198, 32_000])
        #expect(await transport.sentMessages().contains(.text("{\"type\":\"Terminate\"}")))
        #expect(events.contains(where: completedSession))
        #expect(events.compactMap(usageEvent).first?.metrics.first?.quantity == 2)
    }

    @Test("arbitrary short packet boundaries are coalesced and the final tail is padded")
    func shortPacketCoalescingAndResidualPadding() async throws {
        let transport = FakeAssemblyAIWebSocketTransport(
            connectMessages: [beginMessage()],
            terminationMessages: [
                turnMessage(
                    order: 0,
                    transcript: "Boundary.",
                    final: true,
                    formatted: true,
                    words: [word("Boundary.", start: 0, end: 40, confidence: 0.9)]
                ),
                terminationMessage(),
            ]
        )
        let provider = try makeProvider(transport: transport)
        let session = try await concreteSession(provider: provider, route: provider.route())
        let recorder = AssemblyAIEventRecorder(stream: session.events)

        try await session.start()
        try await session.submit(makePacket(frameCount: 1, startFrame: 10_000))
        try await session.submit(makePacket(frameCount: 398, startFrame: 10_001))
        try await session.submit(makePacket(frameCount: 400, startFrame: 10_399))
        #expect(await transport.sentMessages().compactMap(binaryByteCount).isEmpty)
        try await session.finish()

        let binarySizes = await transport.sentMessages().compactMap(binaryByteCount)
        let final = try #require((await recorder.finishedSnapshot()).compactMap(finalEvent).first)
        #expect(binarySizes == [1600])
        #expect(final.utterance.sampleRange.startFrame == 10_000)
        #expect(final.utterance.sampleRange.endFrame == 10_640)
    }

    @Test("more than the former operation mapping cap coalesces without retaining large audio")
    func longSessionMappingCapacity() async throws {
        let transport = FakeAssemblyAIWebSocketTransport(
            connectMessages: [beginMessage()],
            terminationMessages: [terminationMessage()]
        )
        let provider = try makeProvider(transport: transport)
        let session = try await concreteSession(provider: provider, route: provider.route())

        try await session.start()
        for index in 0 ..< 32_769 {
            try await session.submit(makePacket(
                frameCount: 1,
                startFrame: Int64(index) * 16_000,
                operationID: UUID()
            ))
        }
        try await session.finish()

        let binarySizes = await transport.sentMessages().compactMap(binaryByteCount)
        #expect(binarySizes.count == 41)
        #expect(binarySizes.allSatisfy { 1600 ... 32_000 ~= $0 })
    }

    @Test("cancellation closes transport and emits cancelled state")
    func cancellation() async throws {
        let transport = FakeAssemblyAIWebSocketTransport(connectMessages: [beginMessage()])
        let provider = try makeProvider(transport: transport)
        let session = try await concreteSession(provider: provider, route: provider.route())
        let recorder = AssemblyAIEventRecorder(stream: session.events)

        try await session.start()
        try #require(await recorder.waitForSession(.ready))
        await session.cancel()
        let events = await recorder.finishedSnapshot()

        #expect(await transport.wasCancelled())
        #expect(events.contains(where: cancelledSession))
    }
}

private actor FakeAssemblyAIWebSocketTransport: STTWebSocketTransporting {
    private let stream: AsyncStream<STTWebSocketEvent>
    private let continuation: AsyncStream<STTWebSocketEvent>.Continuation
    private let connectMessages: [String]
    private let terminationMessages: [String]
    private var connectedRequest: URLRequest?
    private var messages: [STTWebSocketMessage] = []
    private var cancelled = false
    private var state = STTWebSocketState.disconnected

    init(connectMessages: [String] = [], terminationMessages: [String] = []) {
        self.connectMessages = connectMessages
        self.terminationMessages = terminationMessages
        let pair = AsyncStream<STTWebSocketEvent>.makeStream(bufferingPolicy: .unbounded)
        stream = pair.stream
        continuation = pair.continuation
    }

    func events() -> AsyncStream<STTWebSocketEvent> { stream }
    func currentState() -> STTWebSocketState { state }

    func connect(request: URLRequest) {
        connectedRequest = request
        state = .open
        continuation.yield(.stateChanged(.connecting))
        continuation.yield(.stateChanged(.open))
        connectMessages.forEach { continuation.yield(.message(.text($0))) }
    }

    func send(_ message: STTWebSocketMessage) {
        messages.append(message)
        if message == .text("{\"type\":\"Terminate\"}") {
            terminationMessages.forEach { continuation.yield(.message(.text($0))) }
        }
    }

    func ping() { continuation.yield(.pong) }

    func close(code: Int, reason _: String?) {
        state = .disconnected
        continuation.yield(.closed(code: code))
        continuation.finish()
    }

    func cancel() {
        cancelled = true
        state = .disconnected
        continuation.finish()
    }

    func push(_ message: STTWebSocketMessage) {
        continuation.yield(.message(message))
    }

    func request() -> URLRequest? { connectedRequest }
    func sentMessages() -> [STTWebSocketMessage] { messages }
    func wasCancelled() -> Bool { cancelled }
}

private struct FakeAssemblyAIWebSocketTransportFactory: STTWebSocketTransportFactory {
    let transport: FakeAssemblyAIWebSocketTransport

    func makeTransport() -> any STTWebSocketTransporting { transport }
}

private actor AssemblyAIEventRecorder {
    private var events: [MeetingTranscriptionProviderEvent] = []
    private var completed = false

    init(stream: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>) {
        Task { [weak self] in
            await self?.collect(stream)
        }
    }

    private func collect(_ stream: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>) async {
        do {
            for try await event in stream { events.append(event) }
        } catch {}
        completed = true
    }

    func snapshot() -> [MeetingTranscriptionProviderEvent] { events }

    func waitForEventCount(_ count: Int) async -> Bool {
        await waitUntil { self.events.count >= count }
    }

    func waitForFinalCount(_ count: Int) async -> Bool {
        await waitUntil { self.events.compactMap(finalEvent).count >= count }
    }

    func waitForSession(_ state: MeetingTranscriptionSessionState) async -> Bool {
        await waitUntil {
            self.events.contains { event in
                guard case let .session(session) = event else { return false }
                return session.state == state
            }
        }
    }

    func waitForWarning(code: String) async -> Bool {
        await waitUntil {
            self.events.contains { event in
                guard case let .warning(warning) = event else { return false }
                return warning.code == code
            }
        }
    }

    func finishedSnapshot() async -> [MeetingTranscriptionProviderEvent] {
        _ = await waitUntil { self.completed }
        return events
    }

    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !predicate(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return predicate()
    }
}

private func makeProvider(
    transport: FakeAssemblyAIWebSocketTransport,
    configuration: AssemblyAIStreamingSessionConfiguration? = nil,
    region: AssemblyAIStreamingRegion = .global,
    nowMilliseconds: @escaping @Sendable () -> Int64 = { 1_000_000 },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in try await Task.sleep(for: duration) }
) throws -> AssemblyAIMeetingTranscriptionProvider {
    try AssemblyAIMeetingTranscriptionProvider(
        secretResolver: AssemblyAISecretResolver { try AssemblyAIStreamingCredential(apiKey: "api-key-value") },
        transportFactory: FakeAssemblyAIWebSocketTransportFactory(transport: transport),
        configuration: configuration ?? AssemblyAIStreamingSessionConfiguration(),
        endpoint: assemblyTestEndpoint(region: region),
        model: assemblyTestModel(),
        nowMilliseconds: nowMilliseconds,
        sleep: sleep
    )
}

private func concreteSession(
    provider: AssemblyAIMeetingTranscriptionProvider,
    route: MeetingTranscriptionRoute
) async throws -> AssemblyAIMeetingTrackTranscriptionSession {
    let session = try await provider.makeSession(route: route, context: makeContext())
    return try #require(session as? AssemblyAIMeetingTrackTranscriptionSession)
}

private func makeContext(keyterms: [String] = []) throws -> MeetingTrackTranscriptionContextSnapshot {
    try MeetingTrackTranscriptionContextSnapshot(
        sessionID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        trackID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
        source: .microphone,
        canonicalSampleRateHertz: 16_000,
        channelCount: 1,
        startedAtMilliseconds: 1_000_000,
        keyterms: keyterms
    )
}

private func makePacket(
    frameCount: Int64,
    startFrame: Int64 = 0,
    operationID: UUID = UUID(),
    providerEpoch: MeetingProviderEpoch = .initial,
    isReplay: Bool = false
) throws -> MeetingNormalizedAudioPacket {
    try MeetingNormalizedAudioPacket(
        operationID: operationID,
        sessionID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        trackID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
        source: .microphone,
        sampleRange: MeetingCanonicalSampleRange(
            startFrame: startFrame,
            endFrame: startFrame + frameCount,
            sampleRateHertz: 16_000
        ),
        encoding: .pcmSigned16LittleEndian,
        sampleRateHertz: 16_000,
        channelCount: 1,
        bytes: Data(repeating: 0, count: Int(frameCount * 2)),
        providerEpoch: providerEpoch,
        isReplay: isReplay
    )
}

private func beginMessage(expiresAt: Int64 = 11_800, speakerLabels: Bool = false) -> String {
    "{\"type\":\"Begin\",\"id\":\"CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC\",\"expires_at\":\(expiresAt),\"configuration\":{\"model\":\"universal-3-5-pro\",\"mode\":\"balanced\",\"api_version\":\"2025-05-12\",\"speaker_labels\":\(speakerLabels)}}"
}

private func terminationMessage(audio: Int = 1, session: Int = 1) -> String {
    "{\"type\":\"Termination\",\"audio_duration_seconds\":\(audio),\"session_duration_seconds\":\(session)}"
}

private func word(
    _ text: String,
    start: Int,
    end: Int,
    confidence: Double,
    speaker: String? = nil
) -> String {
    let speakerValue = speaker.map { ",\"speaker\":\"\($0)\"" } ?? ""
    return "{\"text\":\"\(text)\",\"start\":\(start),\"end\":\(end),\"confidence\":\(confidence),\"word_is_final\":true\(speakerValue)}"
}

private func turnMessage(
    order: Int,
    transcript: String,
    final: Bool,
    formatted: Bool,
    speaker: String? = nil,
    words: [String]
) -> String {
    let speakerValue = speaker.map { ",\"speaker_label\":\"\($0)\"" } ?? ""
    return "{\"type\":\"Turn\",\"turn_order\":\(order),\"turn_is_formatted\":\(formatted),\"end_of_turn\":\(final),\"transcript\":\"\(transcript)\",\"end_of_turn_confidence\":\(final ? 1 : 0),\"words\":[\(words.joined(separator: ","))]\(speakerValue)}"
}

private func partialEvent(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionPartialEvent? {
    guard case let .partial(value) = event else { return nil }
    return value
}

private func finalEvent(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionFinalEvent? {
    guard case let .final(value) = event else { return nil }
    return value
}

private func replacementEvent(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionReplacementEvent? {
    guard case let .replacement(value) = event else { return nil }
    return value
}

private func metadataAmendmentEvent(
    _ event: MeetingTranscriptionProviderEvent
) -> MeetingTranscriptionMetadataAmendmentEvent? {
    guard case let .metadataAmendment(value) = event else { return nil }
    return value
}

private func failureEvent(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionFailureEvent? {
    guard case let .failure(value) = event else { return nil }
    return value
}

private func usageEvent(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionUsageEvent? {
    guard case let .usage(value) = event else { return nil }
    return value
}

private func outOfOrderWarning(_ event: MeetingTranscriptionProviderEvent) -> Bool {
    guard case let .warning(value) = event else { return false }
    return value.code == "out-of-order-turn"
}

private func configurationUpdateMessage(_ message: STTWebSocketMessage) -> Bool {
    guard case let .text(value) = message else { return false }
    return value.contains("UpdateConfiguration")
}

private func binaryByteCount(_ message: STTWebSocketMessage) -> Int? {
    guard case let .binary(data) = message else { return nil }
    return data.count
}

private func completedSession(_ event: MeetingTranscriptionProviderEvent) -> Bool {
    guard case let .session(value) = event else { return false }
    return value.state == .completed
}

private func cancelledSession(_ event: MeetingTranscriptionProviderEvent) -> Bool {
    guard case let .session(value) = event else { return false }
    return value.state == .cancelled
}
