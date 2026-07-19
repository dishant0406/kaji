@preconcurrency import AVFoundation
import Foundation

@testable import Kaji

enum MeetingAudioTestFixtures {
    static let sourceID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

    static func source(
        id: UUID = sourceID,
        kind: MeetingSourceKind = .microphone,
        startedAtMilliseconds: Int64 = 1_000
    ) throws -> MeetingAudioSourceIdentity {
        try MeetingAudioSourceIdentity(
            trackID: id,
            kind: kind,
            displayName: kind == .microphone ? "Test microphone" : "Test system audio",
            startedAtMilliseconds: startedAtMilliseconds
        )
    }

    static func buffer(
        sequenceNumber: Int64,
        source: MeetingAudioSourceIdentity? = nil,
        samples: [Float] = [0.25],
        sampleRate: Double = 16_000,
        channelCount: Int = 1,
        capturedAtMilliseconds: Int64? = nil
    ) throws -> MeetingOwnedAudioBuffer {
        let source = try source ?? self.source()
        return try MeetingOwnedAudioBuffer(
            source: source,
            sequenceNumber: sequenceNumber,
            capturedAtMilliseconds: capturedAtMilliseconds ?? source.startedAtMilliseconds + sequenceNumber,
            presentationTimeNanoseconds: sequenceNumber * 1_000_000,
            sampleRate: sampleRate,
            channelCount: channelCount,
            interleavedSamples: samples
        )
    }

    static func chunk(
        operationID: UUID = UUID(),
        source: MeetingAudioSourceIdentity? = nil,
        startFrame: Int64,
        samples: [Float],
        isFinalChunk: Bool = false
    ) throws -> MeetingTranscriptionAudioChunk {
        let source = try source ?? self.source()
        let endFrame = startFrame + Int64(samples.count)
        return MeetingTranscriptionAudioChunk(
            operationID: operationID,
            source: source,
            sampleRange: try MeetingSampleRange(
                startFrame: startFrame,
                endFrame: endFrame,
                sampleRateHertz: MeetingAudioFormat.sampleRateHertz
            ),
            startMilliseconds: source.startedAtMilliseconds + startFrame * 1_000 / 16_000,
            endMilliseconds: source.startedAtMilliseconds + max(1, endFrame * 1_000 / 16_000),
            samples: samples,
            sampleRateHertz: MeetingAudioFormat.sampleRateHertz,
            isFinalChunk: isFinalChunk
        )
    }

    static var model: SpeechInputModel {
        SpeechModelRegistryResources.fallbackModels[0]
    }
}
