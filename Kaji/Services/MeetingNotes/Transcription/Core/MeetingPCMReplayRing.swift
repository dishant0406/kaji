import Foundation

enum MeetingPCMReplayRingError: Error, Equatable {
    case unsupportedEncoding
    case endOfStreamPacket
    case streamMismatch
    case invalidDuration
}

actor MeetingPCMReplayRing {
    static let maximumDurationSeconds = 30

    private let durationSeconds: Int
    private var packets: [MeetingNormalizedAudioPacket] = []
    private var sessionID: UUID?
    private var trackID: UUID?
    private var sampleRateHertz: Int?
    private var channelCount: Int?
    private var encoding: MeetingTranscriptionAudioEncoding?

    init(durationSeconds: Int = MeetingPCMReplayRing.maximumDurationSeconds) throws {
        guard 1 ... Self.maximumDurationSeconds ~= durationSeconds else {
            throw MeetingPCMReplayRingError.invalidDuration
        }
        self.durationSeconds = durationSeconds
    }

    func append(_ packet: MeetingNormalizedAudioPacket) throws {
        guard packet.encoding.bytesPerPCMFramePerChannel != nil else {
            throw MeetingPCMReplayRingError.unsupportedEncoding
        }
        guard !packet.isEndOfStream else {
            throw MeetingPCMReplayRingError.endOfStreamPacket
        }
        if let sessionID {
            guard sessionID == packet.sessionID,
                  trackID == packet.trackID,
                  sampleRateHertz == packet.sampleRateHertz,
                  channelCount == packet.channelCount,
                  encoding == packet.encoding
            else {
                throw MeetingPCMReplayRingError.streamMismatch
            }
        } else {
            sessionID = packet.sessionID
            trackID = packet.trackID
            sampleRateHertz = packet.sampleRateHertz
            channelCount = packet.channelCount
            encoding = packet.encoding
        }
        if let index = packets.firstIndex(where: { $0.operationID == packet.operationID }) {
            guard packets[index] == packet else {
                throw MeetingPCMReplayRingError.streamMismatch
            }
            return
        }
        packets.append(packet)
        packets.sort {
            if $0.sampleRange.startFrame == $1.sampleRange.startFrame {
                return $0.operationID.uuidString < $1.operationID.uuidString
            }
            return $0.sampleRange.startFrame < $1.sampleRange.startFrame
        }
        trimToDuration()
    }

    func replayPackets(overlapping range: MeetingCanonicalSampleRange) throws -> [MeetingNormalizedAudioPacket] {
        guard sampleRateHertz == nil || sampleRateHertz == range.sampleRateHertz else {
            throw MeetingPCMReplayRingError.streamMismatch
        }
        return try packets.filter { $0.sampleRange.overlaps(range) }.map { try $0.replaying() }
    }

    func allReplayPackets() throws -> [MeetingNormalizedAudioPacket] {
        try packets.map { try $0.replaying() }
    }

    func retainedFrameRange() -> Range<Int64>? {
        guard let first = packets.first, let last = packets.last else { return nil }
        return first.sampleRange.startFrame ..< last.sampleRange.endFrame
    }

    func packet(operationID: UUID) -> MeetingNormalizedAudioPacket? {
        packets.first { $0.operationID == operationID }
    }

    func removeAll() {
        packets.removeAll(keepingCapacity: true)
        sessionID = nil
        trackID = nil
        sampleRateHertz = nil
        channelCount = nil
        encoding = nil
    }

    private func trimToDuration() {
        guard let newestEnd = packets.map(\.sampleRange.endFrame).max(), let sampleRateHertz else { return }
        let retainedFrames = Int64(durationSeconds * sampleRateHertz)
        let cutoff = max(0, newestEnd - retainedFrames)
        packets.removeAll { $0.sampleRange.startFrame < cutoff }
    }
}
