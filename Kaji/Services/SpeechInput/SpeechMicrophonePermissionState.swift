@preconcurrency import AVFoundation
import Foundation

enum SpeechMicrophonePermissionState: Equatable {
    case notDetermined
    case allowed
    case denied

    static var current: SpeechMicrophonePermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .allowed
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    var title: String {
        switch self {
        case .notDetermined: "Not requested"
        case .allowed: "Allowed"
        case .denied: "Denied"
        }
    }
}
