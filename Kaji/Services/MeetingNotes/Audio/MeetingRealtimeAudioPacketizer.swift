import Foundation

struct MeetingRealtimeAudioPacketizer {
    static let minimumFrameMilliseconds = 50
    static let maximumFrameMilliseconds = 200

    private let source: MeetingAudioSourceIdentity
    private let sampleRateHertz: Int
    private let frameCount: Int
    private var samples: [Float] = []
    private var sampleHead = 0
    private var pendingStartFrame: Int64 = 0

    init(
        source: MeetingAudioSourceIdentity,
        sampleRateHertz: Int = MeetingAudioFormat.sampleRateHertz,
        frameMilliseconds: Int = 100
    ) throws {
        guard Self.minimumFrameMilliseconds ... Self.maximumFrameMilliseconds ~= frameMilliseconds,
              sampleRateHertz > 0,
              (sampleRateHertz * frameMilliseconds).isMultiple(of: 1000)
        else {
            throw MeetingAudioError.invalidChunkConfiguration
        }
        self.source = source
        self.sampleRateHertz = sampleRateHertz
        frameCount = sampleRateHertz * frameMilliseconds / 1000
    }

    mutating func append(_ buffer: MeetingResampledAudioBuffer) throws -> [MeetingTranscriptionAudioChunk] {
        guard buffer.source == source, !buffer.samples.isEmpty else { throw MeetingAudioError.invalidBuffer }
        samples.append(contentsOf: buffer.samples)
        var packets: [MeetingTranscriptionAudioChunk] = []
        while availableSampleCount >= frameCount {
            let end = sampleHead + frameCount
            try packets.append(makePacket(samples: Array(samples[sampleHead ..< end]), isFinal: false))
            sampleHead = end
            pendingStartFrame += Int64(frameCount)
            compactIfNeeded()
        }
        return packets
    }

    mutating func applyGap(_ gap: MeetingAudioGap) throws -> [MeetingTranscriptionAudioChunk] {
        guard gap.source == source else { throw MeetingAudioError.invalidBuffer }
        let packets = try flush()
        let milliseconds = max(1, gap.endMilliseconds - gap.startMilliseconds)
        pendingStartFrame += Int64((Double(milliseconds) * Double(sampleRateHertz) / 1000).rounded(.up))
        return packets
    }

    mutating func flush() throws -> [MeetingTranscriptionAudioChunk] {
        guard availableSampleCount > 0 else { return [] }
        let packet = try makePacket(samples: Array(samples[sampleHead...]), isFinal: true)
        pendingStartFrame += Int64(availableSampleCount)
        samples.removeAll(keepingCapacity: true)
        sampleHead = 0
        return [packet]
    }

    private var availableSampleCount: Int {
        samples.count - sampleHead
    }

    private func makePacket(samples: [Float], isFinal: Bool) throws -> MeetingTranscriptionAudioChunk {
        let endFrame = pendingStartFrame + Int64(samples.count)
        let range = try MeetingSampleRange(
            startFrame: pendingStartFrame,
            endFrame: endFrame,
            sampleRateHertz: sampleRateHertz
        )
        let start = source.startedAtMilliseconds + pendingStartFrame * 1000 / Int64(sampleRateHertz)
        let end = source.startedAtMilliseconds + (endFrame * 1000 + Int64(sampleRateHertz) - 1)
            / Int64(sampleRateHertz)
        return MeetingTranscriptionAudioChunk(
            operationID: MeetingStableOperationIdentity.uuid(
                sessionID: source.trackID,
                trackID: source.trackID,
                startFrame: pendingStartFrame,
                endFrame: endFrame
            ),
            source: source,
            sampleRange: range,
            startMilliseconds: start,
            endMilliseconds: max(start + 1, end),
            samples: samples,
            sampleRateHertz: sampleRateHertz,
            isFinalChunk: isFinal
        )
    }

    private mutating func compactIfNeeded() {
        guard sampleHead >= frameCount * 4, sampleHead >= samples.count / 2 else { return }
        samples.removeFirst(sampleHead)
        sampleHead = 0
    }
}
