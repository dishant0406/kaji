import AppKit
import Foundation
import Testing

@testable import Kaji

private actor FakeTranscriber: SpeechTranscribing {
    private let batchResults: [String]
    private var batchIndex = 0
    private var liveResults: [String]
    private var liveIndex = 0
    private var finalResult: String?
    private var sessionStarted = false
    private(set) var sessionBeginCount = 0
    private(set) var sessionFinishCount = 0
    private(set) var appendOrder: [String] = []
    private let appendDelayNanoseconds: UInt64
    nonisolated let failSessionStart: Bool

    init(
        batchResults: [String] = [],
        liveResults: [String] = [],
        finalResult: String? = nil,
        appendDelayNanoseconds: UInt64 = 0,
        failSessionStart: Bool = false
    ) {
        self.batchResults = batchResults
        self.liveResults = liveResults
        self.finalResult = finalResult
        self.appendDelayNanoseconds = appendDelayNanoseconds
        self.failSessionStart = failSessionStart
    }

    func prepare(model: SpeechInputModel, progress: SpeechTranscriber.ProgressHandler?) async throws {}

    func transcribe(chunks: [SpeechAudioChunk], model: SpeechInputModel) async throws -> String {
        let result = batchIndex < batchResults.count ? batchResults[batchIndex] : ""
        batchIndex += 1
        if result.isEmpty { throw SpeechInputError.emptyTranscript }
        return result
    }

    func download(model: SpeechInputModel, progress: SpeechTranscriber.ProgressHandler?) async throws {}

    func unload() async {
        sessionStarted = false
    }

    func beginSession(model: SpeechInputModel) async throws {
        if failSessionStart { throw SpeechInputError.modelUnavailable }
        sessionBeginCount += 1
        sessionStarted = true
    }

    func append(chunks: [SpeechAudioChunk], model: SpeechInputModel) async throws -> String? {
        if appendDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: appendDelayNanoseconds)
        }
        appendOrder.append(chunks.map(\.samples).map { $0.first.map { "\($0)" } ?? "empty" }.joined(separator: "|"))
        let result = liveIndex < liveResults.count ? liveResults[liveIndex] : nil
        liveIndex += 1
        return result
    }

    func finishSession(model: SpeechInputModel) async throws -> String {
        sessionFinishCount += 1
        sessionStarted = false
        if let finalResult, !finalResult.isEmpty { return finalResult }
        throw SpeechInputError.emptyTranscript
    }

    func cancelSession() async {
        sessionStarted = false
    }
}

@MainActor
private final class DrainLatch {
    private(set) var fired = false

    func fire() { fired = true }
}

@MainActor
private final class FakeInserter: SpeechInserting {
    var inserted: [String] = []
    var error: Error?

    func insert(_ text: String) throws {
        if let error { throw error }
        inserted.append(text)
    }
}

@MainActor
@Suite("Speech transcript queue")
struct SpeechTranscriptQueueTests {
    private func settings(keepModelWarm: Bool = true, trailingSpace: Bool = false) -> SpeechInputSettings {
        SpeechInputSettings(
            isEnabled: true,
            holdHotkey: SpeechInputSettings.defaults.holdHotkey,
            selectedModelID: SpeechInputModel.defaultID,
            keepModelWarm: keepModelWarm,
            insertTrailingSpace: trailingSpace
        )
    }

private func pending(_ samples: [Float], trailingSpace: Bool) -> SpeechInputPendingChunk {
        SpeechInputPendingChunk(
            chunk: SpeechAudioChunk(samples: samples, sampleRate: 16_000),
            settings: settings(trailingSpace: trailingSpace),
            model: SpeechModelRegistryResources.fallbackModels[0]
        )
    }

    private func releasePending(_ samples: [Float], trailingSpace: Bool = false) -> SpeechInputPendingChunk {
        SpeechInputPendingChunk(
            chunk: SpeechAudioChunk(samples: samples, sampleRate: 16_000),
            settings: settings(trailingSpace: trailingSpace),
            model: releaseModel
        )
    }

    private var releaseModel: SpeechInputModel {
        SpeechInputModel(
            id: "release-test",
            title: "Release Test",
            detail: "Release transcription test model",
            engine: .fluidAudioParakeetTdt,
            registryBaseURL: "https://huggingface.co",
            repo: "test/repo",
            revision: "main",
            cachePath: "release-test",
            estimatedDownloadSize: "1 MiB",
            recommended: false,
            requiredFiles: ["model.mlmodelc"],
            mode: .releaseTranscription
        )
    }

    private func waitForDrain(_ latch: DrainLatch, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !latch.fired, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(latch.fired)
    }

@Test("live chunks are inserted in FIFO order")
    func liveInsertionPreservesOrder() async {
        let inserter = FakeInserter()
        let transcriber = FakeTranscriber(
            liveResults: ["hello ", "world"],
            finalResult: "end",
            appendDelayNanoseconds: 30_000_000
        )
        let queue = SpeechTranscriptQueue(transcriber: transcriber, insertionRouter: inserter)
        queue.start()
        queue.enqueue(pending([0.1], trailingSpace: true))
        queue.enqueue(pending([0.2], trailingSpace: true))
        let latch = DrainLatch()
        queue.finish { latch.fire() }
        await waitForDrain(latch)
#expect(inserter.inserted == ["hello ", "world ", "end "])
        #expect(await transcriber.sessionBeginCount == 1)
    }

    @Test("slow first chunk does not reorder later chunks")
    func slowChunkKeepsOrder() async {
        let inserter = FakeInserter()
        let transcriber = FakeTranscriber(
            liveResults: ["first ", "second ", "third "],
            finalResult: "",
            appendDelayNanoseconds: 40_000_000
        )
        let queue = SpeechTranscriptQueue(transcriber: transcriber, insertionRouter: inserter)
        queue.start()
        queue.enqueue(pending([0.1], trailingSpace: true))
        queue.enqueue(pending([0.2], trailingSpace: true))
        queue.enqueue(pending([0.3], trailingSpace: true))
        let latch = DrainLatch()
        queue.finish { latch.fire() }
        await waitForDrain(latch)
        #expect(inserter.inserted == ["first ", "second ", "third "])
        let order = await transcriber.appendOrder
        #expect(order == ["0.1", "0.2", "0.3"])
    }

    @Test("text accumulates when insertion target is unavailable")
    func accumulateWhenNoTarget() async {
        let inserter = FakeInserter()
        inserter.error = SpeechInputError.noInsertionTarget
        let transcriber = FakeTranscriber(liveResults: ["hello "], finalResult: "world")
        let queue = SpeechTranscriptQueue(transcriber: transcriber, insertionRouter: inserter)
        queue.start()
        queue.enqueue(pending([0.1], trailingSpace: true))
        let latch = DrainLatch()
        queue.finish { latch.fire() }
        await waitForDrain(latch)
        #expect(inserter.inserted.isEmpty)
        #expect(queue.accumulatedText == "hello world ")
    }

    @Test("failed transcription counts down without inserting")
    func failedTranscriptionAccumulatesNothing() async {
        let inserter = FakeInserter()
        let transcriber = FakeTranscriber(liveResults: [])
        let queue = SpeechTranscriptQueue(transcriber: transcriber, insertionRouter: inserter)
queue.start()
        queue.enqueue(pending([0.1], trailingSpace: false))
        let latch = DrainLatch()
        queue.finish { latch.fire() }
        await waitForDrain(latch)
        #expect(inserter.inserted.isEmpty)
        #expect(queue.accumulatedText.isEmpty)
        #expect(queue.isDrained)
    }

    @Test("finish fires onDrained after the stream drains")
    func finishFlushesAccumulated() async {
        let inserter = FakeInserter()
        let transcriber = FakeTranscriber(liveResults: ["hello"])
        let queue = SpeechTranscriptQueue(transcriber: transcriber, insertionRouter: inserter)
queue.start()
        queue.enqueue(pending([0.1], trailingSpace: false))
        #expect(queue.isDrained == false)

        var fired = false
        let latch = DrainLatch()
        queue.finish { fired = true; latch.fire() }
        await waitForDrain(latch)
        #expect(fired)
        #expect(queue.takeAccumulatedText().isEmpty)
    }

    @Test("finish with nothing enqueued fires immediately without a session")
    func finishWhenEmpty() async {
        let inserter = FakeInserter()
        let transcriber = FakeTranscriber()
        let queue = SpeechTranscriptQueue(transcriber: transcriber, insertionRouter: inserter)
        queue.start()
        var fired = false
        queue.finish { fired = true }
        #expect(fired)
        #expect(await transcriber.sessionBeginCount == 0)
    }

    @Test("cancel discards accumulated text and cancels the session")
    func cancelDiscardsAccumulated() async {
        let inserter = FakeInserter()
        let transcriber = FakeTranscriber(liveResults: ["hello"])
        let queue = SpeechTranscriptQueue(transcriber: transcriber, insertionRouter: inserter)
queue.start()
        queue.enqueue(pending([0.1], trailingSpace: false))
        queue.cancel()
        #expect(queue.accumulatedText.isEmpty)
        #expect(queue.isDrained)
    }

    @Test("session begins once per capture and not per chunk")
    func sessionBeginsOnce() async {
        let inserter = FakeInserter()
        let transcriber = FakeTranscriber(liveResults: ["a ", "b ", "c "], finalResult: "d")
        let queue = SpeechTranscriptQueue(transcriber: transcriber, insertionRouter: inserter)
queue.start()
        queue.enqueue(pending([0.1], trailingSpace: true))
        queue.enqueue(pending([0.2], trailingSpace: true))
        queue.enqueue(pending([0.3], trailingSpace: true))
        let latch = DrainLatch()
        queue.finish { latch.fire() }
        await waitForDrain(latch)
        let beginCount = await transcriber.sessionBeginCount
        let finishCount = await transcriber.sessionFinishCount
        #expect(beginCount == 1)
        #expect(finishCount == 1)
#expect(inserter.inserted == ["a ", "b ", "c ", "d "])
    }

    @Test("release mode transcribes per chunk without any session lifecycle")
    func releaseModeSkipsSessions() async {
        let inserter = FakeInserter()
        let transcriber = FakeTranscriber(batchResults: ["hello ", "world"])
        let queue = SpeechTranscriptQueue(transcriber: transcriber, insertionRouter: inserter)
        queue.start()
        queue.enqueue(releasePending([0.1]))
        queue.enqueue(releasePending([0.2]))
        let latch = DrainLatch()
        queue.finish { latch.fire() }
        await waitForDrain(latch)
        let beginCount = await transcriber.sessionBeginCount
        let finishCount = await transcriber.sessionFinishCount
        #expect(beginCount == 0)
        #expect(finishCount == 0)
        #expect(inserter.inserted == ["hello", "world"])
    }

    @Test("release mode session failure still delivers batch transcripts")
    func releaseModeIgnoresSessionFailure() async {
        let inserter = FakeInserter()
        let transcriber = FakeTranscriber(batchResults: ["recovered"], failSessionStart: true)
        let queue = SpeechTranscriptQueue(transcriber: transcriber, insertionRouter: inserter)
        queue.start()
        queue.enqueue(releasePending([0.1]))
        let latch = DrainLatch()
        queue.finish { latch.fire() }
        await waitForDrain(latch)
        #expect(inserter.inserted == ["recovered"])
        #expect(queue.isDrained)
    }
}
