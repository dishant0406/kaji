import Foundation

enum SpeechInputTiming {
    static let chunkIntervalSeconds: TimeInterval = 10
    static let chunkIntervalNanoseconds = UInt64(chunkIntervalSeconds * 1_000_000_000)
    static let releasePollingNanoseconds: UInt64 = 80_000_000
    static let errorResetNanoseconds: UInt64 = 2_000_000_000
}
