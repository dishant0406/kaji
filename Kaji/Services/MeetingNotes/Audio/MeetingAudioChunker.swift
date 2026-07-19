import Foundation

struct MeetingAudioChunkConfiguration: Equatable {
    let durationSeconds: Int
    let overlapSeconds: Int

    init(durationSeconds: Int = 20, overlapSeconds: Int = 2) throws {
        guard (15 ... 30).contains(durationSeconds),
              overlapSeconds >= 0,
              overlapSeconds < durationSeconds
        else {
            throw MeetingAudioError.invalidChunkConfiguration
        }
        self.durationSeconds = durationSeconds
        self.overlapSeconds = overlapSeconds
    }
}

struct MeetingAudioChunker {
    private let source: MeetingAudioSourceIdentity
    private let configuration: MeetingAudioChunkConfiguration
    private let sampleRateHertz: Int
    private let chunkFrameCount: Int
    private let hopFrameCount: Int
    private var samples: [Float] = []
    private var sampleHead = 0
    private var pendingStartFrame: Int64 = 0
    private var lastEmittedEndFrame: Int64 = 0

    init(
        source: MeetingAudioSourceIdentity,
        configuration: MeetingAudioChunkConfiguration,
        sampleRateHertz: Int = MeetingAudioFormat.sampleRateHertz
    ) throws {
        guard sampleRateHertz > 0 else { throw MeetingAudioError.invalidAudioFormat }
        self.source = source
        self.configuration = configuration
        self.sampleRateHertz = sampleRateHertz
        chunkFrameCount = configuration.durationSeconds * sampleRateHertz
        hopFrameCount = (configuration.durationSeconds - configuration.overlapSeconds) * sampleRateHertz
    }

    mutating func append(_ buffer: MeetingResampledAudioBuffer) throws -> [MeetingTranscriptionAudioChunk] {
        guard buffer.source == source, !buffer.samples.isEmpty else { throw MeetingAudioError.invalidBuffer }
        samples.append(contentsOf: buffer.samples)
        var chunks: [MeetingTranscriptionAudioChunk] = []
        while availableSampleCount >= chunkFrameCount {
            let end = sampleHead + chunkFrameCount
            let audio = Array(samples[sampleHead ..< end])
            try chunks.append(makeChunk(samples: audio, startFrame: pendingStartFrame, isFinalChunk: false))
            lastEmittedEndFrame = pendingStartFrame + Int64(chunkFrameCount)
            sampleHead += hopFrameCount
            pendingStartFrame += Int64(hopFrameCount)
            compactIfNeeded()
        }
        return chunks
    }

    mutating func applyGap(_ gap: MeetingAudioGap) throws -> [MeetingTranscriptionAudioChunk] {
        guard gap.source == source else { throw MeetingAudioError.invalidBuffer }
        let chunks = try flush()
        let gapMilliseconds = max(1, gap.endMilliseconds - gap.startMilliseconds)
        let skippedFrames = Int64((Double(gapMilliseconds) * Double(sampleRateHertz) / 1000).rounded(.up))
        pendingStartFrame += skippedFrames
        lastEmittedEndFrame = max(lastEmittedEndFrame, pendingStartFrame)
        return chunks
    }

    mutating func flush() throws -> [MeetingTranscriptionAudioChunk] {
        guard availableSampleCount > 0 else { return [] }
        let endFrame = pendingStartFrame + Int64(availableSampleCount)
        guard endFrame > lastEmittedEndFrame else {
            pendingStartFrame = max(pendingStartFrame, lastEmittedEndFrame)
            resetPending()
            return []
        }
        let audio = Array(samples[sampleHead...])
        let chunk = try makeChunk(samples: audio, startFrame: pendingStartFrame, isFinalChunk: true)
        lastEmittedEndFrame = endFrame
        pendingStartFrame = endFrame
        resetPending()
        return [chunk]
    }

    private var availableSampleCount: Int {
        samples.count - sampleHead
    }

    private func makeChunk(
        samples: [Float],
        startFrame: Int64,
        isFinalChunk: Bool
    ) throws -> MeetingTranscriptionAudioChunk {
        let endFrame = startFrame + Int64(samples.count)
        let sampleRange = try MeetingSampleRange(
            startFrame: startFrame,
            endFrame: endFrame,
            sampleRateHertz: sampleRateHertz
        )
        let startMilliseconds = source.startedAtMilliseconds + startFrame * 1000 / Int64(sampleRateHertz)
        let endOffset = (endFrame * 1000 + Int64(sampleRateHertz) - 1) / Int64(sampleRateHertz)
        let endMilliseconds = max(startMilliseconds + 1, source.startedAtMilliseconds + endOffset)
        return MeetingTranscriptionAudioChunk(
            operationID: MeetingStableOperationIdentity.uuid(
                sessionID: source.trackID,
                trackID: source.trackID,
                startFrame: startFrame,
                endFrame: endFrame
            ),
            source: source,
            sampleRange: sampleRange,
            startMilliseconds: startMilliseconds,
            endMilliseconds: endMilliseconds,
            samples: samples,
            sampleRateHertz: sampleRateHertz,
            isFinalChunk: isFinalChunk
        )
    }

    private mutating func compactIfNeeded() {
        guard sampleHead >= chunkFrameCount, sampleHead >= samples.count / 2 else { return }
        samples.removeFirst(sampleHead)
        sampleHead = 0
    }

    private mutating func resetPending() {
        samples.removeAll(keepingCapacity: true)
        sampleHead = 0
    }
}
