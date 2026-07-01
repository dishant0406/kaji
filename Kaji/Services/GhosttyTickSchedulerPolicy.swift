import Foundation

enum GhosttyTickSchedulerPolicy: Equatable {
    case normal
    case batteryOptimized

    var minimumInterval: TimeInterval {
        switch self {
        case .normal:
            0
        case .batteryOptimized:
            1.0 / 30.0
        }
    }

    func delay(after lastRunDate: Date, now: Date = Date()) -> TimeInterval {
        let remaining = minimumInterval - now.timeIntervalSince(lastRunDate)
        return max(0, remaining)
    }
}

final class GhosttyTickSchedulerPolicyStore: @unchecked Sendable {
    static let shared = GhosttyTickSchedulerPolicyStore()

    private let lock = NSLock()
    private var batteryOptimizedMode = false

    private init() {}

    var policy: GhosttyTickSchedulerPolicy {
        lock.lock()
        defer { lock.unlock() }
        return batteryOptimizedMode ? .batteryOptimized : .normal
    }

    func setBatteryOptimizedMode(_ enabled: Bool) {
        lock.lock()
        batteryOptimizedMode = enabled
        lock.unlock()
    }
}
