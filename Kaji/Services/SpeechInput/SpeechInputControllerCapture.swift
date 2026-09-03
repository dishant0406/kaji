import AppKit
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
            accumulatedLocalText = ""
            transcriptQueue.setKeepModelWarm(settingsStore.settings.keepModelWarm)
            transcriptQueue.start()
            startChunkLoop(for: session)
            startReleaseSafety(for: session, combo: settingsStore.settings.holdHotkey)
        } catch {
            activeSession = nil
            handle(error)
        }
    }

    func finishCapture(reason: SpeechCaptureStopReason) {
        let session = activeSession
        let wasListening = status == .listening
        guard session != nil || wasListening else {
            return
        }
        activeSession = nil
        releasePoller.stop()
        watchdog.stop(session: session)
        chunkLoopTask?.cancel()
        chunkLoopTask = nil
        if wasListening {
            status = .transcribing
        }
        enqueueFinalChunk(reason: reason)
        transcriptQueue.finish { [weak self] in
            self?.completeCaptureFlush()
        }
    }

    private func enqueueFinalChunk(reason: SpeechCaptureStopReason) {
        let model = selectedModel
        let settings = settingsStore.settings
        guard let finalChunk = capture.finish(
            session: activeSession,
            reason: reason
        ), !finalChunk.samples.isEmpty
        else { return }
        transcriptQueue.enqueue(SpeechInputPendingChunk(chunk: finalChunk, settings: settings, model: model))
    }

    func cancelCapture(reason: SpeechCaptureStopReason) {
        let session = activeSession
        activeSession = nil
        releasePoller.stop()
        watchdog.stop(session: session)
        chunkLoopTask?.cancel()
        chunkLoopTask = nil
        transcriptQueue.cancel()
        _ = capture.finish(session: session, reason: reason)
        if case .listening = status {
            status = .idle
        }
        accumulatedLocalText = ""
    }

    private func startChunkLoop(for session: SpeechCaptureSession) {
        let model = selectedModel
        let settings = settingsStore.settings
        chunkLoopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: SpeechInputTiming.chunkIntervalNanoseconds)
                guard let self, !Task.isCancelled, activeSession == session else { return }
                if let chunk = self.capture.snapshotChunk(), !chunk.samples.isEmpty {
                    self.transcriptQueue.enqueue(SpeechInputPendingChunk(chunk: chunk, settings: settings, model: model))
                }
            }
        }
    }

    private func completeCaptureFlush() {
        copyAccumulatedToClipboard()
        accumulatedLocalText = ""
        status = .idle
    }

    private func copyAccumulatedToClipboard() {
        let accumulated = accumulatedLocalText + transcriptQueue.takeAccumulatedText()
        guard !accumulated.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(accumulated, forType: .string)
    }

    private func startReleaseSafety(for session: SpeechCaptureSession, combo: KeyCombo) {
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
