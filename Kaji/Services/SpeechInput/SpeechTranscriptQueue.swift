import Foundation

@MainActor
final class SpeechTranscriptQueue {
    private var transcriber: any SpeechTranscribing
    private var insertionRouter: any SpeechInserting

    private var continuation: AsyncStream<SpeechInputPendingChunk>.Continuation?
    private var consumerTask: Task<Void, Never>?
    private(set) var outstandingCount = 0
    private var onDrainedCallback: (@MainActor () -> Void)?
    private(set) var accumulatedText = ""
    private(set) var lastTranscript = ""

    private var isStreamOpen = false
    private var isTranscribing = false
    private var isCancelled = false
    private var isSessionActive = false
    private var lastModel: SpeechInputModel?
    private var lastSettings: SpeechInputSettings?

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
        outstandingCount = 0
        isStreamOpen = true
        isTranscribing = false
        isCancelled = false
        isSessionActive = false
        lastModel = nil
        lastSettings = nil
        accumulatedText = ""
        lastTranscript = ""
        consumerTask = Task { @MainActor [weak self] in
            for await pending in stream {
                guard let self else { return }
                await self.process(pending)
            }
            self?.completeDrain()
        }
    }

    func enqueue(_ pending: SpeechInputPendingChunk) {
        guard isStreamOpen else { return }
        outstandingCount += 1
        lastModel = pending.model
        lastSettings = pending.settings
        continuation?.yield(pending)
    }

    func finish(onDrained: @escaping @MainActor () -> Void) {
        guard isStreamOpen else {
            onDrained()
            return
        }
        isStreamOpen = false
        continuation?.finish()
        continuation = nil
        if outstandingCount == 0 {
            onDrained()
            completeDrainIfNeeded()
            return
        }
        onDrainedCallback = onDrained
    }

    func cancel() {
        isCancelled = true
        isStreamOpen = false
        continuation?.finish()
        continuation = nil
        consumerTask?.cancel()
        consumerTask = nil
        onDrainedCallback = nil
        outstandingCount = 0
        accumulatedText = ""
        lastTranscript = ""
        endSession(unloading: true)
    }

    var isDrained: Bool { outstandingCount == 0 && !isTranscribing }

    func takeAccumulatedText() -> String {
        let value = accumulatedText
        accumulatedText = ""
        return value
    }

    private func process(_ pending: SpeechInputPendingChunk) async {
        guard !isCancelled else { return }
        isTranscribing = true
        defer {
            isTranscribing = false
            outstandingCount -= 1
        }
        do {
            try await ensureSession(model: pending.model)
            switch pending.model.displayMode {
            case .liveStreaming:
                if let transcript = try await transcriber.append(chunks: [pending.chunk], model: pending.model) {
                    deliver(transcript, settings: pending.settings)
                }
            case .releaseTranscription:
                let transcript = try await transcriber.transcribe(chunks: [pending.chunk], model: pending.model)
                deliver(transcript, settings: pending.settings)
            }
        } catch {
            handleFailure(error)
        }
    }

    private func completeDrain() {
        flushFinalTranscriptAndFire()
    }

    private func completeDrainIfNeeded() {
        guard isSessionActive else { return }
        flushFinalTranscriptAndFire()
    }

    private func flushFinalTranscriptAndFire() {
        Task { @MainActor in
            await self.flushFinalTranscript()
            if self.isCancelled { return }
            let callback = self.onDrainedCallback ?? {}
            self.onDrainedCallback = nil
            callback()
        }
    }

    private func flushFinalTranscript() async {
        guard isSessionActive, let model = lastModel else {
            endSession(unloading: true)
            return
        }
        isSessionActive = false
        do {
            let transcript = try await transcriber.finishSession(model: model)
            deliver(transcript, settings: lastSettings)
        } catch {
            handleFailure(error)
        }
        endSession(unloading: true)
    }

    private func ensureSession(model: SpeechInputModel) async throws {
        guard !isSessionActive else { return }
        try await transcriber.beginSession(model: model)
        isSessionActive = true
    }

    private func endSession(unloading: Bool) {
        guard isSessionActive || unloading else { return }
        isSessionActive = false
        let transcriber = transcriber
        Task(priority: .userInitiated) {
            if unloading {
                await transcriber.unload()
            }
        }
    }

    private func deliver(_ transcript: String, settings: SpeechInputSettings?) {
        guard !transcript.isEmpty else { return }
        lastTranscript = transcript
        let resolvedSettings = settings ?? lastSettings ?? .defaults
        let text = SpeechInsertionPolicy(insertTrailingSpace: resolvedSettings.insertTrailingSpace).preparedText(transcript)
        do {
            try insertionRouter.insert(text)
        } catch {
            if !text.isEmpty { accumulatedText += text }
        }
    }

    private func handleFailure(_ error: Error) {
        DebugFileLog.logError("SpeechInput", error, context: "transcript queue chunk failed")
    }
}
