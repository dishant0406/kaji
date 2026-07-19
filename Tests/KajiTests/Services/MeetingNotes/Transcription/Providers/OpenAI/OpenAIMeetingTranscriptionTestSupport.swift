import Foundation
import Testing

@testable import Kaji
enum OpenAITranscriptionModel: String, CaseIterable {
    case whisper = "whisper-1"
    case miniTranscribe = "gpt-4o-mini-transcribe"
    case transcribe = "gpt-4o-transcribe"
    case diarize = "gpt-4o-transcribe-diarize"
    case realtimeWhisper = "gpt-realtime-whisper"

    var mode: MeetingTranscriptionMode { self == .realtimeWhisper ? .cloudRealtime : .cloudBatch }
    var isDiarizing: Bool { self == .diarize }
}

enum OpenAITranscriptionRegion: String, CaseIterable {
    case global
    case us
    case eu

    var host: String {
        switch self {
        case .global: "api.openai.com"
        case .us: "us.api.openai.com"
        case .eu: "eu.api.openai.com"
        }
    }
}

extension OpenAIMeetingTranscriptionProvider {
    func route(
        model: OpenAITranscriptionModel,
        region: OpenAITranscriptionRegion = .global,
        languageCode: String? = nil,
        retention: MeetingTranscriptionDataRetentionClass? = nil
    ) throws -> MeetingTranscriptionRoute {
        try MeetingTranscriptionRoute(
            providerID: Self.providerID,
            modelID: model.rawValue,
            languageCodes: languageCode.map { [$0] } ?? [],
            regionID: region.rawValue,
            mode: model.mode,
            diarizationEnabled: model.isDiarizing,
            retention: retention ?? .providerDefault
        )
    }
}


struct OpenAITestSecretResolver: OpenAICredentialSecretResolving {
    let result: Result<Data, Error>

    init(_ value: String) {
        result = .success(Data(value.utf8))
    }

    init(error: Error) {
        result = .failure(error)
    }

    func resolveSecret() async throws -> Data {
        try result.get()
    }
}

actor OpenAITestHTTPTransport: OpenAIHTTPTransporting {
    private var responses: [Result<OpenAIHTTPResponse, Error>]
    private(set) var requests: [URLRequest] = []
    private(set) var wasCancelled = false

    init(responses: [Result<OpenAIHTTPResponse, Error>] = []) {
        self.responses = responses
    }

    func execute(_ request: URLRequest) async throws -> OpenAIHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw STTNetworkError.connectionFailed }
        return try responses.removeFirst().get()
    }

    func cancel() {
        wasCancelled = true
    }

    func capturedRequests() -> [URLRequest] {
        requests
    }

    func cancelled() -> Bool {
        wasCancelled
    }
}

struct OpenAITestHTTPTransportFactory: OpenAIHTTPTransportFactory {
    let transport: OpenAITestHTTPTransport

    func makeTransport() -> any OpenAIHTTPTransporting {
        transport
    }
}

actor OpenAITestWebSocketTransport: STTWebSocketTransporting {
    private let stream: AsyncStream<STTWebSocketEvent>
    private let continuation: AsyncStream<STTWebSocketEvent>.Continuation
    private(set) var requests: [URLRequest] = []
    private(set) var messages: [STTWebSocketMessage] = []
    private(set) var pingCount = 0
    private(set) var closeValues: [(Int, String?)] = []
    private(set) var wasCancelled = false
    private var state = STTWebSocketState.disconnected

    init() {
        let pair = AsyncStream<STTWebSocketEvent>.makeStream(bufferingPolicy: .bufferingNewest(512))
        stream = pair.stream
        continuation = pair.continuation
    }

    func events() -> AsyncStream<STTWebSocketEvent> {
        stream
    }

    func currentState() -> STTWebSocketState {
        state
    }

    func connect(request: URLRequest) {
        requests.append(request)
        state = .open
        continuation.yield(.stateChanged(.open))
    }

    func send(_ message: STTWebSocketMessage) {
        messages.append(message)
    }

    func ping() {
        pingCount += 1
        continuation.yield(.pong)
    }

    func close(code: Int, reason: String?) {
        closeValues.append((code, reason))
        state = .disconnected
        continuation.yield(.closed(code: code))
    }

    func cancel() {
        wasCancelled = true
        state = .disconnected
    }

    func push(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let text = try #require(String(data: data, encoding: .utf8))
        continuation.yield(.message(.text(text)))
    }

    func pushText(_ text: String) {
        continuation.yield(.message(.text(text)))
    }

    func capturedMessages() -> [STTWebSocketMessage] {
        messages
    }

    func capturedRequests() -> [URLRequest] {
        requests
    }

    func pings() -> Int {
        pingCount
    }

    func closes() -> [(Int, String?)] {
        closeValues
    }

    func cancelled() -> Bool {
        wasCancelled
    }
}

struct OpenAITestWebSocketTransportFactory: STTWebSocketTransportFactory {
    let transport: OpenAITestWebSocketTransport

    func makeTransport() -> any STTWebSocketTransporting {
        transport
    }
}

final class OpenAITestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64

    init(_ value: Int64) {
        self.value = value
    }

    func now() -> Int64 {
        lock.withLock { value }
    }

    func set(_ value: Int64) {
        lock.withLock { self.value = value }
    }
}

enum OpenAIMeetingTranscriptionTestFixtures {
    static let token = "sk-test-secret-value"
    static let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    static let trackID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    static func endpoint(_ region: OpenAITranscriptionRegion = .global) throws -> MeetingTranscriptionEndpointSnapshot {
        try MeetingTranscriptionEndpointProfile(
            providerID: OpenAIMeetingTranscriptionProvider.providerID,
            displayName: region.rawValue,
            variant: .openAICompatible,
            regionID: region.rawValue,
            restBaseURL: "https://\(region.host)/v1",
            webSocketBaseURL: "wss://\(region.host)/v1",
            discovery: MeetingTranscriptionModelDiscoveryConfiguration(kind: .manual),
            source: .builtIn
        ).snapshot
    }

    static func model(_ model: OpenAITranscriptionModel) throws -> MeetingDiscoveredTranscriptionModel {
        try MeetingDiscoveredTranscriptionModel(
            id: model.rawValue,
            displayName: model.rawValue,
            modes: [model.mode],
            capabilityConfidence: .manual
        )
    }

    static func provider(
        http: OpenAITestHTTPTransport = OpenAITestHTTPTransport(),
        webSocket: OpenAITestWebSocketTransport = OpenAITestWebSocketTransport(),
        secretResolver: any OpenAICredentialSecretResolving = OpenAITestSecretResolver(token),
        stream: Bool = false,
        logprobs: Bool = false,
        maximumResponseBytes: Int = 8 * 1024 * 1024,
        nowMilliseconds: @escaping @Sendable () -> Int64 = { 10_000 },
        selectedModel: OpenAITranscriptionModel = .transcribe,
        region: OpenAITranscriptionRegion = .global
    ) throws -> OpenAIMeetingTranscriptionProvider {
        try OpenAIMeetingTranscriptionProvider(
            secretResolver: secretResolver,
            httpTransportFactory: OpenAITestHTTPTransportFactory(transport: http),
            webSocketTransportFactory: OpenAITestWebSocketTransportFactory(transport: webSocket),
            configuration: OpenAIMeetingTranscriptionConfiguration(
                streamBatchResponses: stream,
                includeRealtimeLogprobs: logprobs,
                maximumResponseBytes: maximumResponseBytes,
                realtimeDrainSeconds: 0.2
            ),
            endpoint: endpoint(region),
            model: Self.model(selectedModel),
            models: try OpenAITranscriptionModel.allCases.map(Self.model),
            mode: selectedModel.mode,
            diarizationEnabled: selectedModel.isDiarizing,
            nowMilliseconds: nowMilliseconds
        )
    }

    static func context(
        sampleRateHertz: Int = 16_000,
        keyterms: [String] = ["Kaji", "Muxy"]
    ) throws -> MeetingTrackTranscriptionContextSnapshot {
        try MeetingTrackTranscriptionContextSnapshot(
            sessionID: sessionID,
            trackID: trackID,
            source: .microphone,
            canonicalSampleRateHertz: sampleRateHertz,
            channelCount: 1,
            startedAtMilliseconds: 1_000,
            keyterms: keyterms
        )
    }

    static func packet(
        operationID: UUID = UUID(),
        startFrame: Int64 = 0,
        frameCount: Int64 = 16_000,
        sampleRateHertz: Int = 16_000,
        byte: UInt8 = 1
    ) throws -> MeetingNormalizedAudioPacket {
        try MeetingNormalizedAudioPacket(
            operationID: operationID,
            sessionID: sessionID,
            trackID: trackID,
            source: .microphone,
            sampleRange: MeetingCanonicalSampleRange(
                startFrame: startFrame,
                endFrame: startFrame + frameCount,
                sampleRateHertz: sampleRateHertz
            ),
            encoding: .pcmSigned16LittleEndian,
            sampleRateHertz: sampleRateHertz,
            channelCount: 1,
            bytes: Data(repeating: byte, count: Int(frameCount) * 2),
            providerEpoch: .initial
        )
    }

    static func response(
        status: Int = 200,
        body: String,
        contentType: String = "application/json",
        headers: [String: String] = [:],
        region: OpenAITranscriptionRegion = .global
    ) throws -> OpenAIHTTPResponse {
        var values = headers
        values["Content-Type"] = contentType
        return try OpenAIHTTPResponse(
            statusCode: status,
            headers: values,
            body: Data(body.utf8),
            finalURL: OpenAIEndpoint.batch(endpoint(region))
        )
    }

    static func collect(
        session: any MeetingTrackTranscriptionSession,
        operation: @escaping @Sendable () async throws -> Void
    ) async throws -> [MeetingTranscriptionProviderEvent] {
        let collector = Task {
            var values: [MeetingTranscriptionProviderEvent] = []
            for try await event in session.events { values.append(event) }
            return values
        }
        do {
            try await operation()
            return try await collector.value
        } catch {
            await session.cancel()
            _ = try? await collector.value
            throw error
        }
    }

    static func waitForMessages(_ count: Int, transport: OpenAITestWebSocketTransport) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while await transport.capturedMessages().count < count, clock.now < deadline {
            try await clock.sleep(for: .milliseconds(5))
        }
        #expect(await transport.capturedMessages().count >= count)
    }
}
