import AppKit
import Testing

@testable import Kaji

private actor FakeTranscriber: SpeechTranscribing {
    private let results: [String]
    private let failures: [Error]
    private var index = 0
    var unloadCount = 0

    init(results: [String] = [], failures: [Error] = []) {
        self.results = results
        self.failures = failures
    }

    func prepare(model: SpeechInputModel, progress: SpeechTranscriber.ProgressHandler?) async throws {}

    func transcribe(chunks: [SpeechAudioChunk], model: SpeechInputModel) async throws -> String {
        if index < failures.count {
            let error = failures[index]
            index += 1
            throw error
        }
        let result = index < results.count ? results[index] : ""
        index += 1
        return result
    }

    func download(model: SpeechInputModel, progress: SpeechTranscriber.ProgressHandler?) async throws {}

    func unload() async {
        unloadCount += 1
    }
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

    private func pending(_ text: String, trailingSpace: Bool = false) -> SpeechInputPendingChunk {
        SpeechInputPendingChunk(
            chunk: SpeechAudioChunk(samples: [0.1], sampleRate: 16_000),
            settings: settings(trailingSpace: trailingSpace),
            model: SpeechModelRegistryResources.fallbackModels[0]
        )
    }

    private func waitForDrain(_ queue: SpeechTranscriptQueue, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !queue.isDrained, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(queue.isDrained)
    }

    @Test("text is inserted live when insertion target is active")
    func liveInsertion() async {
        let inserter = FakeInserter()
        let queue = SpeechTranscriptQueue(transcriber: FakeTranscriber(results: ["hello", "world"]), insertionRouter: inserter)
        queue.start()
        queue.enqueue(pending("hello"))
        queue.enqueue(pending("world"))
        await waitForDrain(queue)
        #expect(inserter.inserted == ["hello", "world"])
        #expect(queue.accumulatedText.isEmpty)
    }

    @Test("text accumulates when insertion target is unavailable")
    func accumulateWhenNoTarget() async {
        let inserter = FakeInserter()
        inserter.error = SpeechInputError.noInsertionTarget
        let queue = SpeechTranscriptQueue(transcriber: FakeTranscriber(results: ["hello ", "world"]), insertionRouter: inserter)
        queue.start()
        queue.enqueue(pending("hello ", trailingSpace: true))
        queue.enqueue(pending("world", trailingSpace: true))
        await waitForDrain(queue)
        #expect(inserter.inserted.isEmpty)
        #expect(queue.accumulatedText == "hello world ")
    }

    @Test("failed transcription counts down without inserting")
    func failedTranscriptionAccumulatesNothing() async {
        let inserter = FakeInserter()
        let queue = SpeechTranscriptQueue(
            transcriber: FakeTranscriber(results: ["hello"], failures: [SpeechInputError.emptyAudio]),
            insertionRouter: inserter
        )
        queue.start()
        queue.enqueue(pending("hello", trailingSpace: false))
        await waitForDrain(queue)
        #expect(inserter.inserted.isEmpty)
        #expect(queue.accumulatedText.isEmpty)
        #expect(queue.isDrained)
    }

    @Test("finish flushes accumulated text on drain")
    func finishFlushesAccumulated() async {
        let inserter = FakeInserter()
        inserter.error = SpeechInputError.noInsertionTarget
        let queue = SpeechTranscriptQueue(transcriber: FakeTranscriber(results: ["hello"]), insertionRouter: inserter)
        queue.start()
        queue.enqueue(pending("hello", trailingSpace: false))
        #expect(queue.isDrained == false)

        var fired = false
        queue.finish { fired = true }
        await waitForDrain(queue)
        #expect(fired)
        let flushed = queue.takeAccumulatedText()
        #expect(flushed == "hello")
        #expect(queue.accumulatedText.isEmpty)
    }

    @Test("onDrained fires immediately when nothing is enqueued")
    func finishWhenEmpty() async {
        let inserter = FakeInserter()
        let queue = SpeechTranscriptQueue(transcriber: FakeTranscriber(), insertionRouter: inserter)
        queue.start()
        var fired = false
        queue.finish { fired = true }
        #expect(fired)
    }

    @Test("cancel discards accumulated text")
    func cancelDiscardsAccumulated() async {
        let inserter = FakeInserter()
        inserter.error = SpeechInputError.noInsertionTarget
        let queue = SpeechTranscriptQueue(transcriber: FakeTranscriber(results: ["hello"]), insertionRouter: inserter)
        queue.start()
        queue.enqueue(pending("hello", trailingSpace: false))
        queue.cancel()
        #expect(queue.accumulatedText.isEmpty)
        #expect(queue.isDrained)
    }
}
