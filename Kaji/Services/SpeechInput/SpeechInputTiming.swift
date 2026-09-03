import Foundation

enum SpeechInputTiming {
    static let chunkIntervalSeconds: TimeInterval = 5
    static let chunkIntervalNanoseconds = UInt64(chunkIntervalSeconds * 1_000_000_000)
    static let maxRecordingSeconds: TimeInterval = 60
    static let maxRecordingNanoseconds = UInt64(maxRecordingSeconds * 1_000_000_000)
    static let releasePollingNanoseconds: UInt64 = 80_000_000
    static let errorResetNanoseconds: UInt64 = 2_000_000_000
}
