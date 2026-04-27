import Foundation

@MainActor
final class GhosttyScrollCoalescer {
    private struct Pending {
        var x: Double
        var y: Double
        var precise: Bool
        var count: Int
    }

    private let batchWindow: TimeInterval
    private let schedule: (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Void
    private var pending: Pending?
    private var scheduled = false

    init() {
        batchWindow = 1.0 / 120.0
        schedule = Self.scheduleOnMain
    }

    init(
        batchWindow: TimeInterval = 1.0 / 120.0,
        schedule: @escaping (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Void
    ) {
        self.batchWindow = batchWindow
        self.schedule = schedule
    }

    func push(
        x: Double,
        y: Double,
        precise: Bool,
        deliver: @escaping (Double, Double, Bool) -> Void
    ) {
        guard x != 0 || y != 0 else { return }

        if var pending, pending.precise == precise {
            pending.x += x
            pending.y += y
            pending.count += 1
            self.pending = pending
        } else {
            flush(deliver, preserveSchedule: scheduled)
            pending = Pending(x: x, y: y, precise: precise, count: 1)
        }

        guard !scheduled else { return }
        scheduled = true
        schedule(pending?.precise == true ? batchWindow : 0) { [weak self] in
            self?.flush(deliver)
        }
    }

    private func flush(
        _ deliver: @escaping (Double, Double, Bool) -> Void,
        preserveSchedule: Bool = false
    ) {
        guard let pending else {
            if !preserveSchedule {
                scheduled = false
            }
            return
        }

        self.pending = nil
        if !preserveSchedule {
            scheduled = false
        }
        GhosttyPerf.debug(
            "scrollFlush precise=\(pending.precise) count=\(pending.count) dx=\(pending.x) dy=\(pending.y)"
        )
        GhosttyPerf.event(
            "scrollFlush",
            "precise=\(pending.precise) count=\(pending.count) dx=\(pending.x) dy=\(pending.y)"
        )
        deliver(pending.x, pending.y, pending.precise)
    }

    private static func scheduleOnMain(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                action()
            }
        }
    }
}
