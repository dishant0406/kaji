import Foundation

extension SpeechInputController {
    func requestMicrophonePermission() {
        guard SpeechMicrophonePermissionState.current == .notDetermined else {
            permissionRefreshToken += 1
            return
        }
        status = .requestingPermission
        Task { [weak self] in
            guard let self else { return }
            let granted = await SpeechAudioCapture.requestMicrophoneAccess()
            permissionRefreshToken += 1
            status = .idle
            if granted {
                ToastState.shared.show("Microphone enabled. Hold shortcut again to dictate.")
            } else {
                handle(SpeechInputError.microphonePermissionDenied)
            }
        }
    }
}
