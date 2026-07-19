import Foundation

enum MeetingTranscriptionSource: String, Codable, CaseIterable, Hashable {
    case microphone
    case systemAudio
    case importedAudio
}

struct MeetingCanonicalSampleRange: Codable, Hashable {
    let startFrame: Int64
    let endFrame: Int64
    let sampleRateHertz: Int

    init(startFrame: Int64, endFrame: Int64, sampleRateHertz: Int) throws {
        guard startFrame >= 0,
              endFrame > startFrame,
              endFrame - startFrame <= Int64(sampleRateHertz) * 600,
              8000 ... 384_000 ~= sampleRateHertz
        else {
            throw MeetingTranscriptionValidationError.invalidAudioPacket("sampleRange")
        }
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.sampleRateHertz = sampleRateHertz
    }

    var frameCount: Int64 {
        endFrame - startFrame
    }

    func overlaps(_ other: Self) -> Bool {
        sampleRateHertz == other.sampleRateHertz && startFrame < other.endFrame && endFrame > other.startFrame
    }

    private enum CodingKeys: String, CodingKey {
        case startFrame
        case endFrame
        case sampleRateHertz
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            startFrame: container.decode(Int64.self, forKey: .startFrame),
            endFrame: container.decode(Int64.self, forKey: .endFrame),
            sampleRateHertz: container.decode(Int.self, forKey: .sampleRateHertz)
        )
    }
}

struct MeetingProviderEpoch: RawRepresentable, Codable, Hashable, Comparable {
    let rawValue: Int

    static let initial = Self(validatedRawValue: 0)

    init?(rawValue: Int) {
        guard rawValue >= 0 else { return nil }
        self.rawValue = rawValue
    }

    private init(validatedRawValue: Int) {
        rawValue = validatedRawValue
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct MeetingNormalizedAudioPacket: Codable, Hashable, Identifiable {
    static let maximumByteCount = 32 * 1024 * 1024

    let id: UUID
    let sessionID: UUID
    let trackID: UUID
    let source: MeetingTranscriptionSource
    let sampleRange: MeetingCanonicalSampleRange
    let encoding: MeetingTranscriptionAudioEncoding
    let sampleRateHertz: Int
    let channelCount: Int
    let bytes: Data
    let providerEpoch: MeetingProviderEpoch
    let isReplay: Bool
    let isEndOfStream: Bool

    init(
        operationID: UUID,
        sessionID: UUID,
        trackID: UUID,
        source: MeetingTranscriptionSource,
        sampleRange: MeetingCanonicalSampleRange,
        encoding: MeetingTranscriptionAudioEncoding,
        sampleRateHertz: Int,
        channelCount: Int,
        bytes: Data,
        providerEpoch: MeetingProviderEpoch,
        isReplay: Bool = false,
        isEndOfStream: Bool = false
    ) throws {
        guard sampleRateHertz == sampleRange.sampleRateHertz,
              8000 ... 384_000 ~= sampleRateHertz,
              1 ... 32 ~= channelCount,
              bytes.count <= Self.maximumByteCount
        else {
            throw MeetingTranscriptionValidationError.invalidAudioPacket("formatOrSize")
        }
        if isEndOfStream {
            guard bytes.isEmpty else {
                throw MeetingTranscriptionValidationError.invalidAudioPacket("endOfStreamBytes")
            }
        } else {
            guard !bytes.isEmpty else {
                throw MeetingTranscriptionValidationError.invalidAudioPacket("bytes")
            }
            if let bytesPerSample = encoding.bytesPerPCMFramePerChannel {
                let expected = sampleRange.frameCount.multipliedReportingOverflow(
                    by: Int64(channelCount * bytesPerSample)
                )
                guard !expected.overflow, expected.partialValue == bytes.count else {
                    throw MeetingTranscriptionValidationError.invalidAudioPacket("pcmByteCount")
                }
            }
        }
        id = operationID
        self.sessionID = sessionID
        self.trackID = trackID
        self.source = source
        self.sampleRange = sampleRange
        self.encoding = encoding
        self.sampleRateHertz = sampleRateHertz
        self.channelCount = channelCount
        self.bytes = bytes
        self.providerEpoch = providerEpoch
        self.isReplay = isReplay
        self.isEndOfStream = isEndOfStream
    }

    var operationID: UUID {
        id
    }

    func replaying(providerEpoch: MeetingProviderEpoch? = nil) throws -> Self {
        try Self(
            operationID: operationID,
            sessionID: sessionID,
            trackID: trackID,
            source: source,
            sampleRange: sampleRange,
            encoding: encoding,
            sampleRateHertz: sampleRateHertz,
            channelCount: channelCount,
            bytes: bytes,
            providerEpoch: providerEpoch ?? self.providerEpoch,
            isReplay: true,
            isEndOfStream: isEndOfStream
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case trackID
        case source
        case sampleRange
        case encoding
        case sampleRateHertz
        case channelCount
        case bytes
        case providerEpoch
        case isReplay
        case isEndOfStream
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            operationID: container.decode(UUID.self, forKey: .id),
            sessionID: container.decode(UUID.self, forKey: .sessionID),
            trackID: container.decode(UUID.self, forKey: .trackID),
            source: container.decode(MeetingTranscriptionSource.self, forKey: .source),
            sampleRange: container.decode(MeetingCanonicalSampleRange.self, forKey: .sampleRange),
            encoding: container.decode(MeetingTranscriptionAudioEncoding.self, forKey: .encoding),
            sampleRateHertz: container.decode(Int.self, forKey: .sampleRateHertz),
            channelCount: container.decode(Int.self, forKey: .channelCount),
            bytes: container.decode(Data.self, forKey: .bytes),
            providerEpoch: container.decode(MeetingProviderEpoch.self, forKey: .providerEpoch),
            isReplay: container.decode(Bool.self, forKey: .isReplay),
            isEndOfStream: container.decode(Bool.self, forKey: .isEndOfStream)
        )
    }
}
