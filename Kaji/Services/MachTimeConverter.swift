import Darwin
import Foundation

enum MachTimeConverter {
    private static let timebase: mach_timebase_info_data_t = {
        var value = mach_timebase_info_data_t()
        mach_timebase_info(&value)
        return value
    }()

    static func toNanoseconds(_ value: UInt64) -> UInt64 {
        if timebase.denom == 0 {
            return value
        }
        return value * UInt64(timebase.numer) / UInt64(timebase.denom)
    }
}
