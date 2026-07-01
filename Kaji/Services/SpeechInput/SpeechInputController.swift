import Foundation

@MainActor
@Observable
final class SpeechInputController {
    static let shared = SpeechInputController()
    var status: SpeechInputStatus = .idle
    var lastTranscript = ""
    var cacheRefreshToken = 0
    var permissionRefreshToken = 0
    @ObservationIgnored let settingsStore: SpeechInputSettingsStore
    @ObservationIgnored let modelRegistry: SpeechModelRegistryStore
    @ObservationIgnored let capture = SpeechAudioCapture()
    @ObservationIgnored let transcriber: SpeechTranscriber
    @ObservationIgnored let hotkeyMonitor = SpeechHotkeyMonitor()
    @ObservationIgnored let lifecycleMonitor = SpeechCaptureLifecycleMonitor()
    @ObservationIgnored let modelTaskRunner: SpeechModelTaskRunner
    @ObservationIgnored let releasePoller = SpeechHotkeyReleasePoller()
    @ObservationIgnored let watchdog = SpeechCaptureWatchdog()
    @ObservationIgnored let cacheStateProvider: (SpeechInputModel) -> SpeechModelCacheState
    @ObservationIgnored var insertionRouter = SpeechInsertionRouter { nil }
    @ObservationIgnored var transcribeTask: Task<Void, Never>?
    @ObservationIgnored var activeSession: SpeechCaptureSession?

    init(
        settingsStore: SpeechInputSettingsStore = .shared,
        modelRegistry: SpeechModelRegistryStore = .shared,
        cacheStateProvider: @escaping (SpeechInputModel) -> SpeechModelCacheState = { $0.cacheState }
    ) {
        let transcriber = SpeechTranscriber()
        self.transcriber = transcriber
        self.settingsStore = settingsStore
        self.modelRegistry = modelRegistry
        self.cacheStateProvider = cacheStateProvider
        modelTaskRunner = SpeechModelTaskRunner(transcriber: transcriber, settingsStore: settingsStore)
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
        watchdog.stop(session: activeSession)
        transcribeTask?.cancel()
        modelTaskRunner.cancel()
        cancelCapture(reason: .controllerStopped)
    }

    func updateEditorProvider(_ provider: @escaping () -> EditorTabState?) {
        insertionRouter = SpeechInsertionRouter(editorProvider: provider)
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
