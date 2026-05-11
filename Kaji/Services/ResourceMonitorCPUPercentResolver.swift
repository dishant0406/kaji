import Foundation

enum ResourceMonitorCPUPercentResolver {
    static func resolve(
        currentCPUTimeNanos: UInt64,
        baselineCPUTimeNanos: UInt64,
        elapsed: TimeInterval
    ) -> Double? {
        guard elapsed > 0, currentCPUTimeNanos >= baselineCPUTimeNanos else { return nil }
        let delta = Double(currentCPUTimeNanos - baselineCPUTimeNanos)
        return (delta / (elapsed * 1_000_000_000)) * 100
    }
}
