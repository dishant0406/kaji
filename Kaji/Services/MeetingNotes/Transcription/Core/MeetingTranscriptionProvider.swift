import Foundation

enum MeetingTranscriptionReadinessState: String, Codable, CaseIterable, Hashable {
    case ready
    case unavailable
    case requiresConfiguration
    case requiresDownload
    case temporarilyUnavailable
}

struct MeetingTranscriptionReadiness: Codable, Hashable {
    let state: MeetingTranscriptionReadinessState
    let reason: String?
    let retryAtMilliseconds: Int64?

    init(
        state: MeetingTranscriptionReadinessState,
        reason: String? = nil,
        retryAtMilliseconds: Int64? = nil
    ) throws {
        guard retryAtMilliseconds.map({ $0 >= 0 }) ?? true else {
            throw MeetingTranscriptionValidationError.invalidValue("readiness.retryAtMilliseconds")
        }
        if state == .ready, reason != nil || retryAtMilliseconds != nil {
            throw MeetingTranscriptionValidationError.invalidValue("readiness.ready")
        }
        self.state = state
        self.reason = try reason.map {
            try MeetingTranscriptionValidation.normalizedText($0, field: "readiness.reason", maximumLength: 1000)
        }
        self.retryAtMilliseconds = retryAtMilliseconds
    }

    private init(unchecked state: MeetingTranscriptionReadinessState) {
        self.state = state
        reason = nil
        retryAtMilliseconds = nil
    }

    static var ready: Self {
        Self(unchecked: .ready)
    }

    static var unavailable: Self {
        Self(unchecked: .unavailable)
    }

    static var requiresDownload: Self {
        Self(unchecked: .requiresDownload)
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case reason
        case retryAtMilliseconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            state: container.decode(MeetingTranscriptionReadinessState.self, forKey: .state),
            reason: container.decodeIfPresent(String.self, forKey: .reason),
            retryAtMilliseconds: container.decodeIfPresent(Int64.self, forKey: .retryAtMilliseconds)
        )
    }
}

protocol MeetingTrackTranscriptionContext: Sendable {
    var sessionID: UUID { get }
    var trackID: UUID { get }
    var source: MeetingTranscriptionSource { get }
    var canonicalSampleRateHertz: Int { get }
    var channelCount: Int { get }
    var startedAtMilliseconds: Int64 { get }
    var keyterms: [String] { get }
}

struct MeetingTrackTranscriptionContextSnapshot: MeetingTrackTranscriptionContext, Codable, Hashable {
    let sessionID: UUID
    let trackID: UUID
    let source: MeetingTranscriptionSource
    let canonicalSampleRateHertz: Int
    let channelCount: Int
    let startedAtMilliseconds: Int64
    let keyterms: [String]

    init(
        sessionID: UUID,
        trackID: UUID,
        source: MeetingTranscriptionSource,
        canonicalSampleRateHertz: Int,
        channelCount: Int,
        startedAtMilliseconds: Int64,
        keyterms: [String] = []
    ) throws {
        guard 8000 ... 384_000 ~= canonicalSampleRateHertz,
              1 ... 32 ~= channelCount,
              startedAtMilliseconds >= 0,
              keyterms.count <= 1000,
              Set(keyterms).count == keyterms.count
        else {
            throw MeetingTranscriptionValidationError.invalidValue("trackContext")
        }
        let normalizedKeyterms = try keyterms.map {
            try MeetingTranscriptionValidation.normalizedText($0, field: "trackContext.keyterm", maximumLength: 200)
        }
        guard normalizedKeyterms.reduce(0, { $0 + $1.utf8.count }) <= 100_000 else {
            throw MeetingTranscriptionValidationError.invalidValue("trackContext.keyterms")
        }
        self.sessionID = sessionID
        self.trackID = trackID
        self.source = source
        self.canonicalSampleRateHertz = canonicalSampleRateHertz
        self.channelCount = channelCount
        self.startedAtMilliseconds = startedAtMilliseconds
        self.keyterms = normalizedKeyterms
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case trackID
        case source
        case canonicalSampleRateHertz
        case channelCount
        case startedAtMilliseconds
        case keyterms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sessionID: container.decode(UUID.self, forKey: .sessionID),
            trackID: container.decode(UUID.self, forKey: .trackID),
            source: container.decode(MeetingTranscriptionSource.self, forKey: .source),
            canonicalSampleRateHertz: container.decode(Int.self, forKey: .canonicalSampleRateHertz),
            channelCount: container.decode(Int.self, forKey: .channelCount),
            startedAtMilliseconds: container.decode(Int64.self, forKey: .startedAtMilliseconds),
            keyterms: container.decode([String].self, forKey: .keyterms)
        )
    }
}

protocol MeetingTranscriptionReadinessChecking: Sendable {
    func readiness(for route: MeetingTranscriptionRoute) async -> MeetingTranscriptionReadiness
}

protocol MeetingTrackTranscriptionSession: Sendable {
    var events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error> { get }
    func start() async throws
    func submit(_ packet: MeetingNormalizedAudioPacket) async throws
    func finish() async throws
    func cancel() async
}

protocol MeetingTranscriptionProvider: MeetingTranscriptionReadinessChecking, Sendable {
    var descriptor: MeetingTranscriptionProviderDescriptor { get }
    func makeSession(
        route: MeetingTranscriptionRoute,
        context: any MeetingTrackTranscriptionContext
    ) async throws -> any MeetingTrackTranscriptionSession
}
