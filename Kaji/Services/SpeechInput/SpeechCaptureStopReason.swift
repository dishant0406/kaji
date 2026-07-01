import Foundation

enum SpeechCaptureStopReason: String, Equatable {
    case shortcutReleased
    case shortcutLost
    case appResignedActive
    case windowResignedKey
    case recordingTimedOut
    case controllerStopped
}
