import Foundation

enum ElevenLabsScribeError: Error, Equatable {
    case invalidConfiguration(String)
    case invalidRoute
    case credentialUnavailable
    case invalidCredential
    case invalidPacket
    case invalidState
    case requestTooLarge
    case responseTooLarge
    case malformedResponse
    case providerFailure(
        code: String,
        classification: MeetingTranscriptionFailureClassification,
        retryAfterMilliseconds: Int64?
    )

    var failureClassification: MeetingTranscriptionFailureClassification {
        switch self {
        case .credentialUnavailable,
             .invalidCredential:
            .authentication
        case .invalidConfiguration,
             .invalidRoute,
             .invalidPacket,
             .invalidState,
             .requestTooLarge,
             .malformedResponse:
            .invalidRequest
        case .responseTooLarge:
            .permanent
        case let .providerFailure(_, classification, _):
            classification
        }
    }

    var retryAfterMilliseconds: Int64? {
        guard case let .providerFailure(_, _, retryAfterMilliseconds) = self else { return nil }
        return retryAfterMilliseconds
    }

    var code: String {
        switch self {
        case .invalidConfiguration: "invalid-configuration"
        case .invalidRoute: "invalid-route"
        case .credentialUnavailable: "credential-unavailable"
        case .invalidCredential: "invalid-credential"
        case .invalidPacket: "invalid-packet"
        case .invalidState: "invalid-state"
        case .requestTooLarge: "request-too-large"
        case .responseTooLarge: "response-too-large"
        case .malformedResponse: "malformed-response"
        case let .providerFailure(code, _, _): code
        }
    }

    var safeMessage: String {
        switch failureClassification {
        case .authentication: "ElevenLabs authentication failed."
        case .authorization: "ElevenLabs rejected access to Scribe."
        case .rateLimited: "ElevenLabs rate limited the transcription request."
        case .quotaExceeded: "The ElevenLabs transcription quota is exhausted."
        case .transient,
             .unavailable: "ElevenLabs transcription is temporarily unavailable."
        case .cancelled: "ElevenLabs transcription was cancelled."
        case .invalidRequest: "ElevenLabs rejected the transcription input."
        case .permanent: "ElevenLabs transcription failed."
        }
    }
}

protocol ElevenLabsScribeCredentialResolving: Sendable {
    func resolveAPIKey() async throws -> Data
}

struct ElevenLabsScribeCredentialProfileResolver: ElevenLabsScribeCredentialResolving {
    let profileID: UUID
    let store: any STTCredentialProfileStoring

    func resolveAPIKey() async throws -> Data {
        do {
            return try store.loadSecret(profileID: profileID)
        } catch STTCredentialStoreError.credentialUnavailable {
            throw ElevenLabsScribeError.credentialUnavailable
        } catch {
            throw ElevenLabsScribeError.credentialUnavailable
        }
    }
}

struct ElevenLabsScribeHTTPResponse: Equatable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    init(statusCode: Int, headers: [String: String] = [:], body: Data) throws {
        guard 100 ... 599 ~= statusCode,
              headers.count <= 128,
              headers.allSatisfy({ $0.key.utf8.count <= 256 && $0.value.utf8.count <= 8192 })
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

protocol ElevenLabsScribeHTTPTransporting: Sendable {
    func execute(_ request: URLRequest, maximumResponseBytes: Int) async throws -> ElevenLabsScribeHTTPResponse
    func cancel() async
}

protocol ElevenLabsScribeHTTPTransportFactory: Sendable {
    func makeTransport() -> any ElevenLabsScribeHTTPTransporting
}

enum ElevenLabsScribeRealtimeCommitStrategy: String {
    case manual
    case vad
}

struct ElevenLabsScribeBatchOptions: Equatable {
    static let maximumSupportedAudioSeconds = 600
    static let maximumSupportedWAVBytes = 32 * 1024 * 1024
    static let maximumSupportedBodyBytes = 34 * 1024 * 1024

    let tagAudioEvents: Bool
    let noVerbatim: Bool
    let speakerCount: Int?
    let maximumAudioSeconds: Int
    let maximumWAVBytes: Int
    let maximumBodyBytes: Int
    let maximumResponseBytes: Int

    init(
        tagAudioEvents: Bool = true,
        noVerbatim: Bool = false,
        speakerCount: Int? = nil,
        maximumAudioSeconds: Int = maximumSupportedAudioSeconds,
        maximumWAVBytes: Int = maximumSupportedWAVBytes,
        maximumBodyBytes: Int = maximumSupportedBodyBytes,
        maximumResponseBytes: Int = 8 * 1024 * 1024
    ) throws {
        guard speakerCount.map({ 1 ... 32 ~= $0 }) ?? true,
              1 ... Self.maximumSupportedAudioSeconds ~= maximumAudioSeconds,
              44 ... Self.maximumSupportedWAVBytes ~= maximumWAVBytes,
              maximumWAVBytes ... Self.maximumSupportedBodyBytes ~= maximumBodyBytes,
              1024 ... 16 * 1024 * 1024 ~= maximumResponseBytes
        else {
            throw ElevenLabsScribeError.invalidConfiguration("batch-options")
        }
        self.tagAudioEvents = tagAudioEvents
        self.noVerbatim = noVerbatim
        self.speakerCount = speakerCount
        self.maximumAudioSeconds = maximumAudioSeconds
        self.maximumWAVBytes = maximumWAVBytes
        self.maximumBodyBytes = maximumBodyBytes
        self.maximumResponseBytes = maximumResponseBytes
    }
}

struct ElevenLabsScribeRealtimeOptions: Equatable {
    static let maximumSupportedSessionSeconds = 14400

    let commitStrategy: ElevenLabsScribeRealtimeCommitStrategy
    let noVerbatim: Bool
    let includeLanguageDetection: Bool
    let vadSilenceThresholdSeconds: Double
    let vadThreshold: Double
    let minimumSpeechDurationMilliseconds: Int
    let minimumSilenceDurationMilliseconds: Int
    let maximumFrameDurationMilliseconds: Int
    let manualCommitWindowSeconds: Int
    let maximumSessionSeconds: Int
    let startTimeoutSeconds: Double
    let finishTimeoutSeconds: Double

    init(
        commitStrategy: ElevenLabsScribeRealtimeCommitStrategy = .manual,
        noVerbatim: Bool = false,
        includeLanguageDetection: Bool = true,
        vadSilenceThresholdSeconds: Double = 1.5,
        vadThreshold: Double = 0.4,
        minimumSpeechDurationMilliseconds: Int = 100,
        minimumSilenceDurationMilliseconds: Int = 100,
        maximumFrameDurationMilliseconds: Int = 1000,
        manualCommitWindowSeconds: Int = 20,
        maximumSessionSeconds: Int = maximumSupportedSessionSeconds,
        startTimeoutSeconds: Double = 15,
        finishTimeoutSeconds: Double = 30
    ) throws {
        guard vadSilenceThresholdSeconds.isFinite,
              0.3 ... 3.0 ~= vadSilenceThresholdSeconds,
              vadThreshold.isFinite,
              0.1 ... 0.9 ~= vadThreshold,
              50 ... 2000 ~= minimumSpeechDurationMilliseconds,
              50 ... 2000 ~= minimumSilenceDurationMilliseconds,
              100 ... 1000 ~= maximumFrameDurationMilliseconds,
              10 ... 25 ~= manualCommitWindowSeconds,
              1 ... Self.maximumSupportedSessionSeconds ~= maximumSessionSeconds,
              startTimeoutSeconds.isFinite,
              1 ... 60 ~= startTimeoutSeconds,
              finishTimeoutSeconds.isFinite,
              1 ... 120 ~= finishTimeoutSeconds
        else {
            throw ElevenLabsScribeError.invalidConfiguration("realtime-options")
        }
        self.commitStrategy = commitStrategy
        self.noVerbatim = noVerbatim
        self.includeLanguageDetection = includeLanguageDetection
        self.vadSilenceThresholdSeconds = vadSilenceThresholdSeconds
        self.vadThreshold = vadThreshold
        self.minimumSpeechDurationMilliseconds = minimumSpeechDurationMilliseconds
        self.minimumSilenceDurationMilliseconds = minimumSilenceDurationMilliseconds
        self.maximumFrameDurationMilliseconds = maximumFrameDurationMilliseconds
        self.manualCommitWindowSeconds = manualCommitWindowSeconds
        self.maximumSessionSeconds = maximumSessionSeconds
        self.startTimeoutSeconds = startTimeoutSeconds
        self.finishTimeoutSeconds = finishTimeoutSeconds
    }
}

enum ElevenLabsScribeKeytermPolicy {
    static func validateBatch(_ keyterms: [String]) throws {
        try validate(keyterms, maximumCount: 1000, maximumCharacters: 50, maximumWords: 5)
    }

    static func validateRealtime(_ keyterms: [String]) throws {
        try validate(keyterms, maximumCount: 50, maximumCharacters: 20, maximumWords: nil)
    }

    private static func validate(
        _ keyterms: [String],
        maximumCount: Int,
        maximumCharacters: Int,
        maximumWords: Int?
    ) throws {
        guard keyterms.count <= maximumCount, Set(keyterms).count == keyterms.count else {
            throw ElevenLabsScribeError.invalidConfiguration("keyterms")
        }
        let forbidden = CharacterSet(charactersIn: "<>{}[]\\")
        for keyterm in keyterms {
            let normalized = keyterm.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized == keyterm,
                  !normalized.isEmpty,
                  normalized.count <= maximumCharacters,
                  !normalized.unicodeScalars.contains(where: {
                      forbidden.contains($0) || CharacterSet.controlCharacters.contains($0)
                  }),
                  maximumWords.map({ normalized.split(whereSeparator: \ .isWhitespace).count <= $0 }) ?? true
            else {
                throw ElevenLabsScribeError.invalidConfiguration("keyterms")
            }
        }
    }
}

enum ElevenLabsScribeIdentity {
    static func derivedUUID(namespace: UUID, index: UInt64) -> UUID {
        var bytes = uuidBytes(namespace)
        var value = index.bigEndian
        withUnsafeBytes(of: &value) { indexBytes in
            for offset in 0 ..< 8 {
                bytes[8 + offset] ^= indexBytes[offset]
            }
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func uuidBytes(_ value: UUID) -> [UInt8] {
        withUnsafeBytes(of: value.uuid) { Array($0) }
    }
}
