import Testing

@testable import Kaji

@Suite("Meeting audio chunking")
struct MeetingAudioChunkerTests {
    @Test("chunks use configured overlap and absolute monotonic timestamps")
    func overlapAndTimestamps() throws {
        let source = try MeetingAudioTestFixtures.source(startedAtMilliseconds: 10_000)
        let configuration = try MeetingAudioChunkConfiguration(durationSeconds: 15, overlapSeconds: 2)
        var chunker = try MeetingAudioChunker(
            source: source,
            configuration: configuration,
            sampleRateHertz: 10
        )
        let input = MeetingResampledAudioBuffer(
            source: source,
            sequenceNumber: 0,
            samples: (0 ..< 280).map(Float.init)
        )

        let chunks = try chunker.append(input)
        let flushed = try chunker.flush()

        #expect(chunks.count == 2)
        #expect(flushed.isEmpty)
        #expect(chunks[0].sampleRange.startFrame == 0)
        #expect(chunks[0].sampleRange.endFrame == 150)
        #expect(chunks[1].sampleRange.startFrame == 130)
        #expect(chunks[1].sampleRange.endFrame == 280)
        #expect(chunks[0].startMilliseconds == 10_000)
        #expect(chunks[0].endMilliseconds == 25_000)
        #expect(chunks[1].startMilliseconds == 23_000)
        #expect(chunks[1].samples.prefix(20) == chunks[0].samples.suffix(20))
    }

    @Test("stop flush emits a partial chunk once")
    func finalFlush() throws {
        let source = try MeetingAudioTestFixtures.source()
        var chunker = try MeetingAudioChunker(
            source: source,
            configuration: MeetingAudioChunkConfiguration(),
            sampleRateHertz: 10
        )
        _ = try chunker.append(MeetingResampledAudioBuffer(
            source: source,
            sequenceNumber: 0,
            samples: [Float](repeating: 0.5, count: 40)
        ))

        let firstFlush = try chunker.flush()
        let secondFlush = try chunker.flush()

        #expect(firstFlush.count == 1)
        #expect(firstFlush[0].isFinalChunk)
        #expect(firstFlush[0].sampleRange.startFrame == 0)
        #expect(firstFlush[0].sampleRange.endFrame == 40)
        #expect(secondFlush.isEmpty)
    }

    @Test("a gap flushes preceding audio and advances the source timeline")
    func gapBoundary() throws {
        let source = try MeetingAudioTestFixtures.source()
        var chunker = try MeetingAudioChunker(
            source: source,
            configuration: MeetingAudioChunkConfiguration(),
            sampleRateHertz: 10
        )
        _ = try chunker.append(MeetingResampledAudioBuffer(
            source: source,
            sequenceNumber: 0,
            samples: [Float](repeating: 1, count: 20)
        ))
        let dropped = try MeetingAudioTestFixtures.buffer(
            sequenceNumber: 1,
            source: source,
            samples: [Float](repeating: 0, count: 16_000),
            capturedAtMilliseconds: 3_000
        )

        let beforeGap = try chunker.applyGap(MeetingAudioGap(buffer: dropped, reason: .backpressure))
        let afterGap = try chunker.append(MeetingResampledAudioBuffer(
            source: source,
            sequenceNumber: 2,
            samples: [Float](repeating: 2, count: 20)
        ))
        let final = try chunker.flush()

        #expect(beforeGap[0].sampleRange == (try MeetingSampleRange(startFrame: 0, endFrame: 20, sampleRateHertz: 10)))
        #expect(afterGap.isEmpty)
        #expect(final[0].sampleRange.startFrame == 30)
        #expect(final[0].sampleRange.endFrame == 50)
    }
}
