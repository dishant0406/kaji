import Foundation

final class SpeechCaptureWatchdog {
    private let queue = DispatchQueue(label: "com.kaji.speech.capture-watchdog")
    private var timer: DispatchSourceTimer?
    private var task: Task<Void, Never>?

    func start(session: SpeechCaptureSession, onTimeout: @escaping @Sendable (SpeechCaptureSession) -> Void) {
        stop()
        let next = DispatchSource.makeTimerSource(queue: queue)
        next.schedule(deadline: .now() + .milliseconds(Int(SpeechInputTiming.maxRecordingSeconds * 1000)))
        next.setEventHandler {
            onTimeout(session)
        }
        timer = next
        next.resume()
        task = Task.detached {
            try? await Task.sleep(nanoseconds: SpeechInputTiming.maxRecordingNanoseconds)
            guard !Task.isCancelled else { return }
            onTimeout(session)
        }
    }

    func stop(session _: SpeechCaptureSession?) {
        stop()
    }

    func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        task?.cancel()
        task = nil
    }
}
