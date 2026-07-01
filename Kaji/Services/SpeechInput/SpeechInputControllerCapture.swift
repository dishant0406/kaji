import Foundation

extension SpeechInputController {
    func beginCapture() {
        guard settingsStore.settings.isEnabled, case .idle = status else {
            return
        }
        let model = selectedModel
        guard cacheStateProvider(model).isReady else {
            setEnabled(false)
            handle(SpeechInputError.modelUnavailable)
            return
        }
        if SpeechMicrophonePermissionState.current == .notDetermined {
            requestMicrophonePermission()
            return
        }
        let session = SpeechCaptureSession.start()
        do {
            activeSession = session
            try capture.start(session: session)
            status = .listening
            startReleaseSafety(for: session, combo: settingsStore.settings.holdHotkey)
        } catch {
            activeSession = nil
            handle(error)
        }
    }

    func finishCapture(reason: SpeechCaptureStopReason) {
        let session = activeSession
        let shouldTranscribe = status == .listening
        guard session != nil || shouldTranscribe else {
            return
        }
        activeSession = nil
        releasePoller.stop()
        watchdog.stop(session: session)
        let chunks = capture.stop(session: session, reason: reason)
        guard shouldTranscribe else {
            status = .idle
            return
        }
        status = .transcribing
        startTranscription(chunks: chunks, settings: settingsStore.settings, model: selectedModel)
    }

    func cancelCapture(reason: SpeechCaptureStopReason) {
        let session = activeSession
        activeSession = nil
        releasePoller.stop()
        watchdog.stop(session: session)
        _ = capture.stop(session: session, reason: reason)
        if case .listening = status { status = .idle }
    }

    func startTranscription(chunks: [SpeechAudioChunk], settings: SpeechInputSettings, model: SpeechInputModel) {
        let transcriber = transcriber
        transcribeTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let transcript = try await transcriber.transcribe(chunks: chunks, model: model)
                let text = SpeechInsertionPolicy(insertTrailingSpace: settings.insertTrailingSpace).preparedText(transcript)
                try await MainActor.run { try self?.completeTranscript(transcript: transcript, text: text) }
                if !settings.keepModelWarm { await transcriber.unload() }
            } catch {
                await transcriber.unload()
                await MainActor.run { self?.handle(error) }
            }
            await MainActor.run { self?.transcribeTask = nil }
        }
    }

    func completeTranscript(transcript: String, text: String) throws {
        try insertionRouter.insert(text)
        lastTranscript = transcript
        status = .idle
    }

    func startReleaseSafety(for session: SpeechCaptureSession, combo: KeyCombo) {
        releasePoller.start(combo: combo) { [weak self] reason in
            guard let self, activeSession == session else { return }
            finishCapture(reason: reason)
        }
        watchdog.start(session: session) { [weak self] timedOutSession in
            Task { @MainActor [weak self] in
                guard let self, activeSession == timedOutSession else { return }
                ToastState.shared.show("Speech recording stopped after 60 seconds")
                finishCapture(reason: .recordingTimedOut)
            }
        }
    }
}
