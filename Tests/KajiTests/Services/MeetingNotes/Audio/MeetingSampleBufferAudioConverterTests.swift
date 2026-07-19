@preconcurrency import AVFoundation
import Testing

@testable import Kaji

@Suite("Meeting sample buffer audio conversion")
struct MeetingSampleBufferAudioConverterTests {
    @Test("PCM copy owns interleaved samples independently of the source buffer")
    func ownedCopy() throws {
        let source = try MeetingAudioTestFixtures.source()
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        let channels = try #require(buffer.floatChannelData)
        buffer.frameLength = 3
        channels[0][0] = 0.1
        channels[0][1] = 0.2
        channels[0][2] = 0.3
        channels[1][0] = 0.4
        channels[1][1] = 0.5
        channels[1][2] = 0.6

        let owned = try MeetingSampleBufferAudioCopier().copy(
            buffer,
            source: source,
            sequenceNumber: 4,
            capturedAtMilliseconds: 1_500
        )
        channels[0][0] = 1

        #expect(owned.frameCount == 3)
        #expect(owned.channelCount == 2)
        #expect(owned.interleavedSamples == [0.1, 0.4, 0.2, 0.5, 0.3, 0.6])
    }

    @Test("AVAudioConverter resamples stereo input to 16 kHz mono float")
    func resampling() throws {
        let source = try MeetingAudioTestFixtures.source()
        let frameCount = 4_800
        var samples: [Float] = []
        samples.reserveCapacity(frameCount * 2)
        for frame in 0 ..< frameCount {
            let sample = sin(Float(frame) * 0.01)
            samples.append(sample)
            samples.append(sample)
        }
        let input = try MeetingAudioTestFixtures.buffer(
            sequenceNumber: 0,
            source: source,
            samples: samples,
            sampleRate: 48_000,
            channelCount: 2
        )

        let resampler = MeetingAudioResampler()
        let output = try resampler.convert(input)
        let tail = try resampler.finish(source: source)
        let convertedSamples = output.samples + (tail?.samples ?? [])

        #expect(output.source == source)
        #expect((1_590 ... 1_610).contains(convertedSamples.count))
        #expect(convertedSamples.allSatisfy { $0.isFinite })
        #expect(convertedSamples.contains { abs($0) > 0.1 })
    }

    @Test("invalid buffers are rejected before entering the queue")
    func invalidInput() throws {
        let source = try MeetingAudioTestFixtures.source()
        #expect(throws: MeetingAudioError.invalidBuffer) {
            _ = try MeetingOwnedAudioBuffer(
                source: source,
                sequenceNumber: 0,
                capturedAtMilliseconds: 1_000,
                presentationTimeNanoseconds: nil,
                sampleRate: 16_000,
                channelCount: 2,
                interleavedSamples: [0]
            )
        }
    }

    @Test("copy failure metadata creates a source-aware timeline gap")
    func copyFailureGap() throws {
        let source = try MeetingAudioTestFixtures.source()
        let gap = MeetingAudioGap(
            source: source,
            sequenceNumber: 42,
            capturedAtMilliseconds: 2_500,
            frameCount: 480,
            sampleRate: 48_000,
            reason: .conversionFailure
        )

        #expect(gap.source == source)
        #expect(gap.firstSequenceNumber == 42)
        #expect(gap.lastSequenceNumber == 42)
        #expect(gap.droppedFrameCount == 480)
        #expect(gap.startMilliseconds == 2_500)
        #expect(gap.endMilliseconds == 2_510)
        #expect(gap.reason == .conversionFailure)
    }
}
