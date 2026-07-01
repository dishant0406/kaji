import Foundation

enum SpeechInputTiming {
    static let maxRecordingSeconds: TimeInterval = 60
    static let releasePollingNanoseconds: UInt64 = 80_000_000
    static let maxRecordingNanoseconds = UInt64(maxRecordingSeconds * 1_000_000_000)
    static let errorResetNanoseconds: UInt64 = 2_000_000_000
}
