import Foundation

@MainActor
@Observable
final class SpeechInputController {
    static let shared = SpeechInputController()
    var status: SpeechInputStatus = .idle
    var cacheRefreshToken = 0
    var permissionRefreshToken = 0
    @ObservationIgnored let settingsStore: SpeechInputSettingsStore
    @ObservationIgnored let modelRegistry: SpeechModelRegistryStore
    @ObservationIgnored var capture: any SpeechCapturing
    @ObservationIgnored var transcriber: any SpeechTranscribing
    @ObservationIgnored let hotkeyMonitor = SpeechHotkeyMonitor()
    @ObservationIgnored let lifecycleMonitor = SpeechCaptureLifecycleMonitor()
    @ObservationIgnored let modelTaskRunner: SpeechModelTaskRunner
    @ObservationIgnored let releasePoller = SpeechHotkeyReleasePoller()
    @ObservationIgnored let cacheStateProvider: (SpeechInputModel) -> SpeechModelCacheState
    @ObservationIgnored var insertionRouter: any SpeechInserting = SpeechInsertionRouter { nil }
    @ObservationIgnored var activeSession: SpeechCaptureSession?
    @ObservationIgnored var chunkLoopTask: Task<Void, Never>?
    @ObservationIgnored let transcriptQueue: SpeechTranscriptQueue
    @ObservationIgnored var accumulatedLocalText = ""

    init(
        settingsStore: SpeechInputSettingsStore = .shared,
        modelRegistry: SpeechModelRegistryStore = .shared,
        cacheStateProvider: @escaping (SpeechInputModel) -> SpeechModelCacheState = { $0.cacheState }
    ) {
        let capturer = SpeechAudioCapture()
        let transcriber = SpeechTranscriber()
        self.capture = capturer
        self.transcriber = transcriber
        self.settingsStore = settingsStore
        self.modelRegistry = modelRegistry
        self.cacheStateProvider = cacheStateProvider
        transcriptQueue = SpeechTranscriptQueue(transcriber: transcriber, insertionRouter: SpeechInsertionRouter { nil })
        modelTaskRunner = SpeechModelTaskRunner(transcriber: transcriber, settingsStore: settingsStore)
    }

    convenience init(
        capture: any SpeechCapturing,
        transcriber: any SpeechTranscribing,
        inserter: any SpeechInserting,
        settingsStore: SpeechInputSettingsStore,
        modelRegistry: SpeechModelRegistryStore,
        cacheStateProvider: @escaping (SpeechInputModel) -> SpeechModelCacheState
    ) {
        self.init(settingsStore: settingsStore, modelRegistry: modelRegistry, cacheStateProvider: cacheStateProvider)
        self.capture = capture
        self.transcriber = transcriber
        transcriptQueue.replace(transcriber: transcriber, insertionRouter: inserter)
    }

    func start() {
        hotkeyMonitor.start(
            onPress: { [weak self] in self?.beginCapture() },
            onRelease: { [weak self] reason in self?.finishCapture(reason: reason) }
        )
        lifecycleMonitor.start { [weak self] reason in
            Task { @MainActor [weak self] in
                self?.hotkeyMonitor.forceRelease(reason)
                self?.finishCapture(reason: reason)
            }
        }
    }

    func stop() {
        hotkeyMonitor.stop()
        lifecycleMonitor.stop()
        releasePoller.stop()
        modelTaskRunner.cancel()
        cancelCapture(reason: .controllerStopped)
    }

    func updateEditorProvider(_ provider: @escaping () -> EditorTabState?) {
        transcriptQueue.replace(insertionRouter: SpeechInsertionRouter(editorProvider: provider))
    }

    func setEnabled(_ enabled: Bool) {
        if enabled, !cacheStateProvider(selectedModel).isReady {
            settingsStore.update { $0.isEnabled = false }
            handle(SpeechInputError.modelUnavailable)
            return
        }
        settingsStore.update { $0.isEnabled = enabled }
    }

    func selectModel(id: String) {
        let model = modelRegistry.model(for: id)
        settingsStore.update { settings in
            settings.selectedModelID = model.id
            if !cacheStateProvider(model).isReady { settings.isEnabled = false }
        }
        cacheRefreshToken += 1
    }

    func reloadModelRegistry() {
        modelRegistry.reload()
        let model = selectedModel
        settingsStore.update { settings in
            settings.selectedModelID = model.id
            if !cacheStateProvider(model).isReady { settings.isEnabled = false }
        }
        cacheRefreshToken += 1
    }

    var selectedModel: SpeechInputModel {
        settingsStore.settings.selectedModel(in: modelRegistry.models)
    }
}
