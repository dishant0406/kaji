import Foundation

extension SpeechInputController {
    func handle(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        status = .error(message)
        ToastState.shared.show(message)
        DebugFileLog.logError("SpeechInput", error, context: "operation failed")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: SpeechInputTiming.errorResetNanoseconds)
            guard let self, case .error = status else { return }
            status = .idle
        }
    }
}
