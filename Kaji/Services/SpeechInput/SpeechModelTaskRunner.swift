import Foundation

@MainActor
final class SpeechModelTaskRunner {
    typealias StatusHandler = @MainActor @Sendable (SpeechInputStatus) -> Void
    typealias CacheHandler = @MainActor @Sendable () -> Void
    typealias ErrorHandler = @MainActor @Sendable (Error) -> Void

    private let transcriber: any SpeechTranscribing
    private let settingsStore: SpeechInputSettingsStore
    private var task: Task<Void, Never>?

    init(transcriber: any SpeechTranscribing, settingsStore: SpeechInputSettingsStore) {
        self.transcriber = transcriber
        self.settingsStore = settingsStore
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func run(
        kind: SpeechModelTaskKind,
        model: SpeechInputModel,
        onStatus: @escaping StatusHandler,
        onCacheChanged: @escaping CacheHandler,
        onError: @escaping ErrorHandler
    ) {
        guard task == nil else { return }
        onStatus(kind.status(kind.initialProgress))
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await run(kind: kind, model: model, onStatus: onStatus)
                onCacheChanged()
                onStatus(.idle)
            } catch is CancellationError {
            } catch {
                onError(error)
            }
            task = nil
        }
    }

    private func run(
        kind: SpeechModelTaskKind,
        model: SpeechInputModel,
        onStatus: @escaping StatusHandler
    ) async throws {
        switch kind {
        case .download:
            try await transcriber.download(model: model, progress: progressHandler(kind, onStatus))
            ToastState.shared.show("Speech model downloaded")
        case .prepare:
            try await transcriber.prepare(model: model, progress: progressHandler(kind, onStatus))
            if !settingsStore.settings.keepModelWarm {
                await transcriber.unload()
            }
            ToastState.shared.show("Speech model ready")
        }
    }

    private func progressHandler(
        _ kind: SpeechModelTaskKind,
        _ onStatus: @escaping StatusHandler
    ) -> SpeechTranscriber.ProgressHandler {
        { progress in
            Task { @MainActor in onStatus(kind.status(progress)) }
        }
    }
}
