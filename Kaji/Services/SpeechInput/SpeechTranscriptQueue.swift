import Foundation

@MainActor
final class SpeechTranscriptQueue {
    private var transcriber: any SpeechTranscribing
    private var insertionRouter: any SpeechInserting

    private var continuation: AsyncStream<SpeechInputPendingChunk>.Continuation?
    private var consumerTask: Task<Void, Never>?
    private(set) var enqueuedCount = 0
    private var onDrained: (@MainActor () -> Void)?
    private(set) var accumulatedText = ""
    private(set) var lastTranscript = ""

    init(transcriber: any SpeechTranscribing, insertionRouter: any SpeechInserting) {
        self.transcriber = transcriber
        self.insertionRouter = insertionRouter
    }

    func replace(transcriber: any SpeechTranscribing, insertionRouter: any SpeechInserting) {
        self.transcriber = transcriber
        self.insertionRouter = insertionRouter
    }

    func replace(insertionRouter: any SpeechInserting) {
        self.insertionRouter = insertionRouter
    }

    func start() {
        let (stream, continuation) = AsyncStream.makeStream(of: SpeechInputPendingChunk.self)
        self.continuation = continuation
        consumerTask = Task { @MainActor [weak self] in
            for await pending in stream {
                guard let self else { return }
                self.process(pending)
            }
        }
    }

    func enqueue(_ pending: SpeechInputPendingChunk) {
        enqueuedCount += 1
        continuation?.yield(pending)
    }

    func finish(onDrained: @escaping @MainActor () -> Void) {
        continuation?.finish()
        continuation = nil
        consumerTask = nil
        if enqueuedCount == 0 {
            onDrained()
            return
        }
        self.onDrained = onDrained
    }

    func cancel() {
        continuation?.finish()
        continuation = nil
        consumerTask?.cancel()
        consumerTask = nil
        onDrained = nil
        enqueuedCount = 0
        accumulatedText = ""
    }

    var isDrained: Bool {
        enqueuedCount == 0
    }

    func onDrained(_ block: @escaping @MainActor () -> Void) {
        if enqueuedCount == 0 {
            block()
            return
        }
        onDrained = block
    }

    func takeAccumulatedText() -> String {
        let value = accumulatedText
        accumulatedText = ""
        return value
    }

    private func process(_ pending: SpeechInputPendingChunk) {
        let transcriber = transcriber
        Task(priority: .userInitiated) { [weak self] in
            do {
                let transcript = try await transcriber.transcribe(chunks: [pending.chunk], model: pending.model)
                let text = SpeechInsertionPolicy(insertTrailingSpace: pending.settings.insertTrailingSpace)
                    .preparedText(transcript)
                await MainActor.run {
                    guard let self else { return }
                    self.lastTranscript = transcript
                    self.deliver(text)
                    self.decrement()
                }
                if !pending.settings.keepModelWarm { await transcriber.unload() }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.decrement()
                }
            }
        }
    }

    private func deliver(_ text: String) {
        do {
            try insertionRouter.insert(text)
        } catch {
            if !text.isEmpty { accumulatedText += text }
        }
    }

    private func decrement() {
        enqueuedCount -= 1
        if enqueuedCount == 0 {
            let onComplete = onDrained
            onDrained = nil
            onComplete?()
        }
    }
}
