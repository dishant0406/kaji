
import Foundation
import Testing

@testable import Kaji
typealias DeepgramNova3MeetingTranscriptionProvider = DeepgramMeetingTranscriptionProvider

extension DeepgramMeetingTranscriptionProvider {
    static let monolingualModelID = "nova-3"
    static let multilingualModelID = "nova-3-multilingual"
    static let globalRegionID = "global"
    static let europeRegionID = "europe"
    static let australiaRegionID = "australia"
}

struct StaticDeepgramSecretResolver: DeepgramAPIKeyResolving {
    let secret: Data

    func resolveAPIKey(profileID _: UUID) throws -> Data {
        secret
    }
}

struct SingleDeepgramTransportFactory: STTWebSocketTransportFactory {
    let transport: FakeDeepgramTransport

    func makeTransport() -> any STTWebSocketTransporting {
        transport
    }
}

final class ManualDeepgramTicks: @unchecked Sendable {
    let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        let pair = AsyncStream<Void>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func tick() {
        continuation.yield()
    }
}

actor FakeDeepgramTransport: STTWebSocketTransporting, DeepgramWebSocketResponseMetadataProviding {
    private let eventStream: AsyncStream<STTWebSocketEvent>
    private let eventContinuation: AsyncStream<STTWebSocketEvent>.Continuation
    private let metadata: DeepgramWebSocketResponseMetadata?
    private var state = STTWebSocketState.disconnected
    private var request: URLRequest?
    private var messages: [STTWebSocketMessage] = []
    private var closes = 0
    private var cancellations = 0
    private var connections = 0

    init(responseMetadata: DeepgramWebSocketResponseMetadata? = nil) {
        metadata = responseMetadata
        let pair = AsyncStream<STTWebSocketEvent>.makeStream(bufferingPolicy: .bufferingNewest(256))
        eventStream = pair.stream
        eventContinuation = pair.continuation
    }

    func events() -> AsyncStream<STTWebSocketEvent> {
        eventStream
    }

    func currentState() -> STTWebSocketState {
        state
    }

    func connect(request: URLRequest) {
        connections += 1
        self.request = request
        state = .connecting
        eventContinuation.yield(.stateChanged(.connecting))
        state = .open
        eventContinuation.yield(.stateChanged(.open))
    }

    func send(_ message: STTWebSocketMessage) throws {
        guard state == .open else { throw STTNetworkError.protocolViolation }
        messages.append(message)
        if message == .text("{\"type\":\"CloseStream\"}") {
            let metadata = "{\"type\":\"Metadata\",\"request_id\":" +
                "\"44444444-4444-4444-4444-444444444444\",\"duration\":0,\"channels\":1}"
            eventContinuation.yield(.message(.text(metadata)))
        }
    }

    func ping() throws {
        guard state == .open else { throw STTNetworkError.protocolViolation }
        eventContinuation.yield(.pong)
    }

    func close(code _: Int, reason _: String?) {
        closes += 1
        state = .closing
        eventContinuation.yield(.stateChanged(.closing))
        state = .disconnected
        eventContinuation.yield(.closed(code: 1000))
        eventContinuation.yield(.stateChanged(.disconnected))
    }

    func cancel() {
        cancellations += 1
        state = .disconnected
        eventContinuation.yield(.stateChanged(.disconnected))
    }

    func deepgramResponseMetadata() -> DeepgramWebSocketResponseMetadata? {
        metadata
    }

    func emit(_ event: STTWebSocketEvent) {
        eventContinuation.yield(event)
    }

    func capturedRequest() -> URLRequest? {
        request
    }

    func sentMessages() -> [STTWebSocketMessage] {
        messages
    }

    func closeCallCount() -> Int {
        closes
    }

    func cancelCallCount() -> Int {
        cancellations
    }

    func connectCallCount() -> Int {
        connections
    }
}

enum DeepgramTranscriptEventKind: Equatable {
    case partial
    case replacement
    case final
}

struct DeepgramTranscriptEventValue {
    let kind: DeepgramTranscriptEventKind
    let utterance: MeetingTranscriptionUtterance
}

struct DeepgramTestWord {
    let text: String
    let start: Double
    let end: Double
    let speaker: Int
    let language: String
}

enum DeepgramTestError: Error {
    case timedOut
    case invalidFixture
}

private func deepgramTestEndpoint() throws -> MeetingTranscriptionEndpointSnapshot {
    try MeetingTranscriptionEndpointProfile(
        providerID: DeepgramMeetingTranscriptionProvider.providerID,
        displayName: "Deepgram Test",
        variant: .deepgram,
        regionID: DeepgramMeetingTranscriptionProvider.globalRegionID,
        restBaseURL: "https://api.deepgram.test",
        webSocketBaseURL: "wss://api.deepgram.test",
        discovery: MeetingTranscriptionModelDiscoveryConfiguration(kind: .manual),
        source: .builtIn
    ).snapshot
}

private func deepgramTestModel() throws -> MeetingDiscoveredTranscriptionModel {
    try MeetingDiscoveredTranscriptionModel(
        id: DeepgramMeetingTranscriptionProvider.multilingualModelID,
        displayName: "Test Model",
        modes: [.cloudRealtime],
        capabilityConfidence: .manual
    )
}

func deepgramProvider(
    configuration: DeepgramNova3Configuration? = nil,
    transport: FakeDeepgramTransport,
    ticks: ManualDeepgramTicks? = nil
) throws -> DeepgramNova3MeetingTranscriptionProvider {
    let resolvedConfiguration = try configuration ?? DeepgramNova3Configuration(credentialProfileID: UUID())
    return try DeepgramMeetingTranscriptionProvider(
        configuration: resolvedConfiguration,
        secretResolver: StaticDeepgramSecretResolver(secret: Data("secret-key".utf8)),
        transportFactory: SingleDeepgramTransportFactory(transport: transport),
        endpoint: deepgramTestEndpoint(),
        model: deepgramTestModel(),
        nowMilliseconds: { 20_000 },
        makeKeepAliveTicks: { _ in ticks?.stream ?? AsyncStream { _ in } }
    )
}

func deepgramContext(
    keyterms: [String] = [],
    sessionID: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
    trackID: UUID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
) throws -> MeetingTrackTranscriptionContextSnapshot {
    try MeetingTrackTranscriptionContextSnapshot(
        sessionID: sessionID,
        trackID: trackID,
        source: .systemAudio,
        canonicalSampleRateHertz: 16_000,
        channelCount: 1,
        startedAtMilliseconds: 10_000,
        keyterms: keyterms
    )
}

func deepgramPacket(
    context: MeetingTrackTranscriptionContextSnapshot,
    startFrame: Int64,
    frameCount: Int64,
    operationID: UUID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
    providerEpoch: MeetingProviderEpoch = .initial,
    isReplay: Bool = false
) throws -> MeetingNormalizedAudioPacket {
    try MeetingNormalizedAudioPacket(
        operationID: operationID,
        sessionID: context.sessionID,
        trackID: context.trackID,
        source: context.source,
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

func deepgramResult(
    transcript: String,
    duration: Double,
    isFinal: Bool,
    speechFinal: Bool,
    languages: [String] = ["en"],
    words: [DeepgramTestWord]
) throws -> String {
    let wordValues = words.map { word in
        [
            "word": word.text,
            "punctuated_word": word.text,
            "start": word.start,
            "end": word.end,
            "confidence": 0.98,
            "speaker": word.speaker,
            "speaker_confidence": 0.9,
            "language": word.language
        ] as [String: Any]
    }
    let value: [String: Any] = [
        "type": "Results",
        "channel_index": [0, 1],
        "duration": duration,
        "start": 0.0,
        "is_final": isFinal,
        "speech_final": speechFinal,
        "channel": [
            "alternatives": [[
                "transcript": transcript,
                "confidence": 0.97,
                "languages": languages,
                "words": wordValues
            ]]
        ],
        "metadata": [
            "request_id": "44444444-4444-4444-4444-444444444444",
            "model_info": ["name": "nova-3", "version": "1", "arch": "nova-3"],
            "model_uuid": "55555555-5555-5555-5555-555555555555"
        ],
        "from_finalize": false
    ]
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    guard let result = String(data: data, encoding: .utf8) else {
        throw DeepgramTestError.invalidFixture
    }
    return result
}

func runDeepgramFinal(
    context: MeetingTrackTranscriptionContextSnapshot
) async throws -> MeetingTranscriptionUtterance {
    let transport = FakeDeepgramTransport()
    let provider = try deepgramProvider(transport: transport)
    let route = try MeetingTranscriptionRoute(
        providerID: DeepgramNova3MeetingTranscriptionProvider.providerID,
        modelID: DeepgramNova3MeetingTranscriptionProvider.multilingualModelID,
        languageCodes: ["en", "es"],
        regionID: DeepgramNova3MeetingTranscriptionProvider.globalRegionID,
        mode: .cloudRealtime,
        diarizationEnabled: true,
        retention: .none
    )
    let session = try await provider.makeSession(route: route, context: context)
    let collector = collectDeepgramEvents(session.events)
    try await session.start()
    try await session.submit(try deepgramPacket(context: context, startFrame: 3_200, frameCount: 4_800))
    let words = [
        DeepgramTestWord(text: "hola", start: 0.01, end: 0.05, speaker: 0, language: "es"),
        DeepgramTestWord(text: "Kaji", start: 0.06, end: 0.11, speaker: 1, language: "en"),
        DeepgramTestWord(text: "gracias", start: 0.12, end: 0.18, speaker: 0, language: "es")
    ]
    let result = try deepgramResult(
        transcript: "hola Kaji gracias",
        duration: 0.2,
        isFinal: true,
        speechFinal: true,
        languages: ["es", "en"],
        words: words
    )
    await transport.emit(.message(.text(result)))
    try await Task.sleep(for: .milliseconds(30))
    try await session.finish()
    let events = try await collector.value
    return try #require(events.compactMap(deepgramTranscriptEvent).last?.utterance)
}

func collectDeepgramEvents(
    _ stream: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>
) -> Task<[MeetingTranscriptionProviderEvent], any Error> {
    Task {
        var events: [MeetingTranscriptionProviderEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

func waitForDeepgram(
    _ condition: @escaping @Sendable () async -> Bool
) async throws {
    for _ in 0 ..< 100 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw DeepgramTestError.timedOut
}

func deepgramSessionState(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionSessionState? {
    guard case let .session(value) = event else { return nil }
    return value.state
}

func deepgramTranscriptEvent(_ event: MeetingTranscriptionProviderEvent) -> DeepgramTranscriptEventValue? {
    switch event {
    case let .partial(value):
        DeepgramTranscriptEventValue(kind: .partial, utterance: value.utterance)
    case let .replacement(value):
        DeepgramTranscriptEventValue(kind: .replacement, utterance: value.utterance)
    case let .final(value):
        DeepgramTranscriptEventValue(kind: .final, utterance: value.utterance)
    default:
        nil
    }
}

func deepgramFailure(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionFailureEvent? {
    guard case let .failure(value) = event else { return nil }
    return value
}

func deepgramWarning(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionWarningEvent? {
    guard case let .warning(value) = event else { return nil }
    return value
}

func deepgramRateLimit(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionRateLimitEvent? {
    guard case let .rateLimit(value) = event else { return nil }
    return value
}

func deepgramUsage(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionUsageEvent? {
    guard case let .usage(value) = event else { return nil }
    return value
}

func deepgramSessionEvent(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionSessionEvent? {
    guard case let .session(value) = event else { return nil }
    return value
}
