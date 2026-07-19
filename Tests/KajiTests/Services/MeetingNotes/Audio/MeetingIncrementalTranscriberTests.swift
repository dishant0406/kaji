import Foundation
import Testing

@testable import Kaji

@Suite("Incremental meeting transcription")
struct MeetingIncrementalTranscriberTests {
    @Test("chunks are transcribed in order into core transcript segments")
    func ordering() async throws {
        let runtime = MeetingSpeechTranscriberMock(responses: ["first", "second"])
        let recorder = MeetingRuntimeEventRecorder()
        let sessionID = UUID()
        let router = try makeRouter(runtime: runtime, sessionID: sessionID, recorder: recorder)
        let firstID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let secondID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let firstChunk = try MeetingAudioTestFixtures.chunk(
            operationID: firstID,
            startFrame: 0,
            samples: [1, 1]
        )
        let secondChunk = try MeetingAudioTestFixtures.chunk(
            operationID: secondID,
            startFrame: 2,
            samples: [2, 2]
        )

        try await router.submit(
            firstChunk.normalizedPacket(sessionID: sessionID),
            context: firstChunk.transcriptionContext(sessionID: sessionID)
        )
        try await router.submit(
            secondChunk.normalizedPacket(sessionID: sessionID),
            context: secondChunk.transcriptionContext(sessionID: sessionID)
        )
        await router.finish()

        let segments = await recorder.finalSegments()
        #expect(segments.map(\.id) == [firstID, secondID])
        #expect(segments.map(\.text) == ["first", "second"])
        #expect(segments[0].sampleRange.startFrame == 0)
        #expect(segments[1].sampleRange.startFrame == 2)
        #expect(segments[0].trackID == MeetingAudioTestFixtures.sourceID)
        #expect(segments.map(\.isFinal) == [true, true])
        #expect(await runtime.observedFirstSamples() == [1, 2])
        #expect(await runtime.prepareCount() == 1)
    }

    @Test("pipeline flushes remaining audio at stop without retaining the meeting")
    func pipelineFlush() async throws {
        let queue = try MeetingAudioEventQueue(audioCapacity: 4)
        let runtime = MeetingSpeechTranscriberMock(responses: ["full", "tail"])
        let recorder = MeetingAudioPipelineRecorder()
        let pipeline = try makePipeline(
            queue: queue,
            runtime: runtime,
            recorder: recorder,
            configuration: MeetingAudioChunkConfiguration(durationSeconds: 15, overlapSeconds: 2)
        )
        let source = try MeetingAudioTestFixtures.source()
        await pipeline.start()
        await queue.enqueue(try MeetingAudioTestFixtures.buffer(
            sequenceNumber: 0,
            source: source,
            samples: [Float](repeating: 0.25, count: 128_000)
        ))
        await queue.enqueue(try MeetingAudioTestFixtures.buffer(
            sequenceNumber: 1,
            source: source,
            samples: [Float](repeating: 0.5, count: 128_000)
        ))
        await queue.finish()
        await pipeline.waitUntilFinished()

        let segments = await recorder.segments()
        #expect(segments.map(\.text) == ["full", "tail"])
        #expect(segments[0].sampleRange.startFrame == 0)
        #expect(segments[0].sampleRange.endFrame == 240_000)
        #expect(segments[1].sampleRange.startFrame == 208_000)
        #expect(segments[1].sampleRange.endFrame == 256_000)
        #expect(await recorder.failures().isEmpty)
    }

    @Test("pipeline cancellation reaches an in-flight transcription")
    func cancellation() async throws {
        let queue = try MeetingAudioEventQueue(audioCapacity: 2)
        let runtime = MeetingSpeechTranscriberMock(responses: [], blocksUntilCancelled: true)
        let recorder = MeetingAudioPipelineRecorder()
        let pipeline = try makePipeline(queue: queue, runtime: runtime, recorder: recorder)
        await pipeline.start()
        await queue.enqueue(try MeetingAudioTestFixtures.buffer(
            sequenceNumber: 0,
            samples: [Float](repeating: 0.5, count: 320_000)
        ))
        await runtime.waitUntilTranscriptionStarts()

        await pipeline.cancel()

        #expect(await runtime.cancellationCount() == 1)
        #expect(await recorder.segments().isEmpty)
    }

    @Test("pipeline drain timeout cancels stalled transcription")
    func drainTimeout() async throws {
        let queue = try MeetingAudioEventQueue(audioCapacity: 2)
        let runtime = MeetingSpeechTranscriberMock(responses: [], blocksUntilCancelled: true)
        let recorder = MeetingAudioPipelineRecorder()
        let pipeline = try makePipeline(queue: queue, runtime: runtime, recorder: recorder)
        await pipeline.start()
        await queue.enqueue(try MeetingAudioTestFixtures.buffer(
            sequenceNumber: 0,
            samples: [Float](repeating: 0.5, count: 320_000)
        ))
        await runtime.waitUntilTranscriptionStarts()

        let result = await pipeline.waitUntilFinished(timeout: .milliseconds(10))
        for _ in 0 ..< 100 {
            if await runtime.cancellationCount() > 0 { break }
            await Task.yield()
        }

        #expect(result == .timedOut)
        #expect(await runtime.cancellationCount() == 1)
        #expect(await recorder.segments().isEmpty)
    }

    @Test("cancelling a drain wait cancels stalled transcription")
    func drainCancellation() async throws {
        let queue = try MeetingAudioEventQueue(audioCapacity: 2)
        let runtime = MeetingSpeechTranscriberMock(responses: [], blocksUntilCancelled: true)
        let recorder = MeetingAudioPipelineRecorder()
        let pipeline = try makePipeline(queue: queue, runtime: runtime, recorder: recorder)
        await pipeline.start()
        await queue.enqueue(try MeetingAudioTestFixtures.buffer(
            sequenceNumber: 0,
            samples: [Float](repeating: 0.5, count: 320_000)
        ))
        await runtime.waitUntilTranscriptionStarts()
        let waiter = Task {
            await pipeline.waitUntilFinished(timeout: .seconds(30))
        }

        waiter.cancel()
        let result = await waiter.value
        for _ in 0 ..< 100 {
            if await runtime.cancellationCount() > 0 { break }
            await Task.yield()
        }

        #expect(result == .cancelled)
        #expect(await runtime.cancellationCount() == 1)
        #expect(await recorder.segments().isEmpty)
    }

    private func makeRouter(
        runtime: MeetingSpeechTranscriberMock,
        sessionID _: UUID,
        recorder: MeetingRuntimeEventRecorder
    ) throws -> MeetingTranscriptionRuntimeRouter {
        let provider = try FluidAudioMeetingTranscriptionProvider(
            models: [MeetingAudioTestFixtures.model],
            isModelCached: { _ in true },
            makeTranscriber: { runtime },
            nowMilliseconds: { 50_000 }
        )
        return try MeetingTranscriptionRuntimeRouter(
            provider: provider,
            route: provider.route(modelID: MeetingAudioTestFixtures.model.id),
            eventHandler: { await recorder.record($0) }
        )
    }

    private func makePipeline(
        queue: MeetingAudioEventQueue,
        runtime: MeetingSpeechTranscriberMock,
        recorder: MeetingAudioPipelineRecorder,
        configuration: MeetingAudioChunkConfiguration? = nil
    ) throws -> MeetingAudioProcessingPipeline {
        let provider = try FluidAudioMeetingTranscriptionProvider(
            models: [MeetingAudioTestFixtures.model],
            isModelCached: { _ in true },
            makeTranscriber: { runtime }
        )
        let sessionID = UUID()
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: provider,
            route: provider.route(modelID: MeetingAudioTestFixtures.model.id)
        ) { event in
            switch event {
            case let .partial(segment), let .final(segment):
                await recorder.record(.transcript(segment))
            case let .failure(failure):
                await recorder.record(.failure(MeetingAudioCaptureFailure(
                    domain: "Kaji.MeetingAudio.Transcription",
                    code: 1,
                    message: failure.message
                )))
            case .committedMetadata,
                 .metadataAmendment,
                 .failureRange:
                return
            case .usage, .rateLimit, .warning, .session, .health:
                return
            }
        }
        return MeetingAudioProcessingPipeline(
            queue: queue,
            configuration: try configuration ?? MeetingAudioChunkConfiguration(),
            transcriptionRouter: router,
            transcriptionSessionID: sessionID,
            eventHandler: { await recorder.record($0) }
        )
    }
}

private actor MeetingSpeechTranscriberMock: FluidAudioMeetingTranscribing {
    private var responses: [String]
    private let blocksUntilCancelled: Bool
    private var prepared = 0
    private var firstSamples: [Float] = []
    private var startedTranscriptions = 0
    private var cancellations = 0

    init(responses: [String], blocksUntilCancelled: Bool = false) {
        self.responses = responses
        self.blocksUntilCancelled = blocksUntilCancelled
    }

    func prepare(model _: SpeechInputModel, progress _: SpeechTranscriber.ProgressHandler?) async throws {
        prepared += 1
    }

    func transcribe(chunks: [SpeechAudioChunk], model _: SpeechInputModel) async throws -> String {
        firstSamples.append(chunks.first?.samples.first ?? 0)
        startedTranscriptions += 1
        if blocksUntilCancelled {
            while !Task.isCancelled {
                await Task.yield()
            }
            cancellations += 1
            throw CancellationError()
        }
        guard !responses.isEmpty else { throw SpeechInputError.emptyTranscript }
        return responses.removeFirst()
    }

    func observedFirstSamples() -> [Float] {
        firstSamples
    }

    func prepareCount() -> Int {
        prepared
    }

    func cancellationCount() -> Int {
        cancellations
    }

    func waitUntilTranscriptionStarts() async {
        while startedTranscriptions == 0 {
            await Task.yield()
        }
    }
}

private actor MeetingRuntimeEventRecorder {
    private var events: [MeetingTranscriptionRuntimeEvent] = []

    func record(_ event: MeetingTranscriptionRuntimeEvent) {
        events.append(event)
    }

    func finalSegments() -> [MeetingTranscriptSegment] {
        events.compactMap { event in
            guard case let .final(segment) = event else { return nil }
            return segment
        }
    }
}

private actor MeetingAudioPipelineRecorder {
    private var events: [MeetingAudioPipelineEvent] = []

    func record(_ event: MeetingAudioPipelineEvent) {
        events.append(event)
    }

    func segments() -> [MeetingTranscriptSegment] {
        events.compactMap { event in
            guard case let .transcript(segment) = event else { return nil }
            return segment
        }
    }

    func failures() -> [MeetingAudioCaptureFailure] {
        events.compactMap { event in
            guard case let .failure(failure) = event else { return nil }
            return failure
        }
    }
}
