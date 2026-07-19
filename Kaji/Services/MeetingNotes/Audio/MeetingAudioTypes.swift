import Foundation

enum MeetingAudioError: Error, Equatable {
    case invalidAudioFormat
    case invalidBuffer
    case invalidChunkConfiguration
    case conversionFailed
    case captureAlreadyRunning
    case captureNotRunning
    case microphonePermissionDenied
    case streamSetupFailed(String)
}

struct MeetingAudioSourceIdentity: Hashable {
    let trackID: UUID
    let kind: MeetingSourceKind
    let displayName: String
    let startedAtMilliseconds: Int64

    init(
        trackID: UUID,
        kind: MeetingSourceKind,
        displayName: String,
        startedAtMilliseconds: Int64
    ) throws {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == .microphone || kind == .systemAudio,
              !normalizedName.isEmpty,
              normalizedName.count <= 120,
              startedAtMilliseconds >= 0
        else {
            throw MeetingAudioError.invalidAudioFormat
        }
        self.trackID = trackID
        self.kind = kind
        self.displayName = normalizedName
        self.startedAtMilliseconds = startedAtMilliseconds
    }

    var track: MeetingSourceTrack {
        MeetingSourceTrack(
            id: trackID,
            kind: kind,
            displayName: displayName,
            sampleRateHertz: MeetingAudioFormat.sampleRateHertz,
            channelCount: MeetingAudioFormat.channelCount,
            startedAtMilliseconds: startedAtMilliseconds
        )
    }
}

enum MeetingAudioFormat {
    static let sampleRateHertz = 16000
    static let channelCount = 1
}

struct MeetingOwnedAudioBuffer {
    let source: MeetingAudioSourceIdentity
    let sequenceNumber: Int64
    let capturedAtMilliseconds: Int64
    let presentationTimeNanoseconds: Int64?
    let sampleRate: Double
    let channelCount: Int
    let interleavedSamples: [Float]

    init(
        source: MeetingAudioSourceIdentity,
        sequenceNumber: Int64,
        capturedAtMilliseconds: Int64,
        presentationTimeNanoseconds: Int64?,
        sampleRate: Double,
        channelCount: Int,
        interleavedSamples: [Float]
    ) throws {
        guard sequenceNumber >= 0,
              capturedAtMilliseconds >= source.startedAtMilliseconds,
              sampleRate.isFinite,
              sampleRate > 0,
              channelCount > 0,
              channelCount <= 32,
              !interleavedSamples.isEmpty,
              interleavedSamples.count.isMultiple(of: channelCount),
              interleavedSamples.allSatisfy(\.isFinite)
        else {
            throw MeetingAudioError.invalidBuffer
        }
        self.source = source
        self.sequenceNumber = sequenceNumber
        self.capturedAtMilliseconds = capturedAtMilliseconds
        self.presentationTimeNanoseconds = presentationTimeNanoseconds
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.interleavedSamples = interleavedSamples
    }

    var frameCount: Int {
        interleavedSamples.count / channelCount
    }
}

struct MeetingResampledAudioBuffer {
    let source: MeetingAudioSourceIdentity
    let sequenceNumber: Int64
    let samples: [Float]
}

struct MeetingTranscriptionAudioChunk {
    let operationID: UUID
    let source: MeetingAudioSourceIdentity
    let sampleRange: MeetingSampleRange
    let startMilliseconds: Int64
    let endMilliseconds: Int64
    let samples: [Float]
    let sampleRateHertz: Int
    let isFinalChunk: Bool
}

enum MeetingAudioGapReason: String {
    case backpressure
    case conversionFailure
    case transcriptionFailure
}

struct MeetingAudioGap: Equatable {
    let source: MeetingAudioSourceIdentity
    var firstSequenceNumber: Int64
    var lastSequenceNumber: Int64
    var droppedBufferCount: Int
    var droppedFrameCount: Int64
    var startMilliseconds: Int64
    var endMilliseconds: Int64
    let reason: MeetingAudioGapReason

    init(buffer: MeetingOwnedAudioBuffer, reason: MeetingAudioGapReason) {
        let durationMilliseconds = Int64((Double(buffer.frameCount) * 1000 / buffer.sampleRate).rounded(.up))
        source = buffer.source
        firstSequenceNumber = buffer.sequenceNumber
        lastSequenceNumber = buffer.sequenceNumber
        droppedBufferCount = 1
        droppedFrameCount = Int64(buffer.frameCount)
        startMilliseconds = buffer.capturedAtMilliseconds
        endMilliseconds = buffer.capturedAtMilliseconds + max(1, durationMilliseconds)
        self.reason = reason
    }

    init(
        source: MeetingAudioSourceIdentity,
        sequenceNumber: Int64,
        capturedAtMilliseconds: Int64,
        frameCount: Int,
        sampleRate: Double,
        reason: MeetingAudioGapReason
    ) {
        let retainedFrameCount = max(1, frameCount)
        let retainedSampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48000
        let durationMilliseconds = Int64(
            (Double(retainedFrameCount) * 1000 / retainedSampleRate).rounded(.up)
        )
        self.source = source
        firstSequenceNumber = max(0, sequenceNumber)
        lastSequenceNumber = max(0, sequenceNumber)
        droppedBufferCount = 1
        droppedFrameCount = Int64(retainedFrameCount)
        startMilliseconds = max(source.startedAtMilliseconds, capturedAtMilliseconds)
        endMilliseconds = startMilliseconds + max(1, durationMilliseconds)
        self.reason = reason
    }

    mutating func merge(_ other: Self) {
        firstSequenceNumber = min(firstSequenceNumber, other.firstSequenceNumber)
        lastSequenceNumber = max(lastSequenceNumber, other.lastSequenceNumber)
        let bufferCount = droppedBufferCount.addingReportingOverflow(other.droppedBufferCount)
        droppedBufferCount = bufferCount.overflow ? .max : bufferCount.partialValue
        let frameCount = droppedFrameCount.addingReportingOverflow(other.droppedFrameCount)
        droppedFrameCount = frameCount.overflow ? .max : frameCount.partialValue
        startMilliseconds = min(startMilliseconds, other.startMilliseconds)
        endMilliseconds = max(endMilliseconds, other.endMilliseconds)
    }
}

struct MeetingAudioCaptureFailure: Error, Equatable {
    let domain: String
    let code: Int
    let message: String
    let occurrenceCount: Int
    let source: MeetingAudioSourceIdentity?
    let sequenceNumber: Int64?
    let capturedAtMilliseconds: Int64?
    let frameCount: Int?

    init(
        domain: String,
        code: Int,
        message: String,
        occurrenceCount: Int = 1,
        source: MeetingAudioSourceIdentity? = nil,
        sequenceNumber: Int64? = nil,
        capturedAtMilliseconds: Int64? = nil,
        frameCount: Int? = nil
    ) {
        self.domain = String(domain.prefix(200))
        self.code = code
        self.message = String(message.prefix(1000))
        self.occurrenceCount = max(1, occurrenceCount)
        self.source = source
        self.sequenceNumber = sequenceNumber
        self.capturedAtMilliseconds = capturedAtMilliseconds
        self.frameCount = frameCount
    }

    func merging(_ other: Self) -> Self {
        let combinedCount = occurrenceCount.addingReportingOverflow(other.occurrenceCount)
        let retainedCount = combinedCount.overflow ? Int.max : combinedCount.partialValue
        if domain == other.domain, code == other.code, message == other.message, source == other.source {
            return Self(
                domain: domain,
                code: code,
                message: message,
                occurrenceCount: retainedCount,
                source: source,
                sequenceNumber: other.sequenceNumber ?? sequenceNumber,
                capturedAtMilliseconds: other.capturedAtMilliseconds ?? capturedAtMilliseconds,
                frameCount: other.frameCount ?? frameCount
            )
        }
        return Self(
            domain: "Kaji.MeetingAudio.MultipleFailures",
            code: 1,
            message: "Multiple audio capture failures occurred.",
            occurrenceCount: retainedCount
        )
    }
}

enum MeetingAudioQueueEvent {
    case audio(MeetingOwnedAudioBuffer)
    case gap(MeetingAudioGap)
    case failure(MeetingAudioCaptureFailure)
}

enum MeetingAudioPipelineEvent {
    case partialTranscript(MeetingTranscriptSegment)
    case transcript(MeetingTranscriptSegment)
    case committedMetadata(MeetingCommittedTranscriptMetadata)
    case metadataAmendment(MeetingCommittedTranscriptMetadata)
    case transcriptionUsage(MeetingTranscriptionUsageEvent)
    case transcriptionRateLimit(MeetingTranscriptionRateLimitEvent)
    case transcriptionWarning(MeetingTranscriptionWarningEvent)
    case transcriptionSession(MeetingTranscriptionSessionEvent)
    case transcriptionTrackHealth(MeetingTranscriptionTrackHealthEvent)
    case transcriptionFailure(MeetingTranscriptionFailureEvent)
    case transcriptionFailureRange(MeetingTranscriptionFailureEvent, MeetingCanonicalSampleRange)
    case gap(MeetingAudioGap)
    case failure(MeetingAudioCaptureFailure)
}
