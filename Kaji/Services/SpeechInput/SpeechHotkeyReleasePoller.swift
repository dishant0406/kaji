import Foundation

@MainActor
final class SpeechHotkeyReleasePoller {
    private var task: Task<Void, Never>?

    func start(combo: KeyCombo, onRelease: @escaping @MainActor (SpeechCaptureStopReason) -> Void) {
        stop()
        task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: SpeechInputTiming.releasePollingNanoseconds)
                guard !Task.isCancelled else { return }
                if !SpeechHotkeyPhysicalState.isPressed(combo) {
                    onRelease(.shortcutLost)
                    return
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
