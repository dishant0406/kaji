import AppKit

final class GhosttyTickScheduler: @unchecked Sendable {
    private enum State {
        case idle
        case scheduled
        case running
    }

    private let lock = NSLock()
    private let dispatch: (@escaping @MainActor () -> Void) -> Void
    private var state: State = .idle
    private var needsAnotherRun = false

    init(dispatch: @escaping (@escaping @MainActor () -> Void) -> Void = GhosttyTickScheduler.dispatchOnMain) {
        self.dispatch = dispatch
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        let shouldDispatch: Bool

        lock.lock()
        switch state {
        case .idle:
            state = .scheduled
            shouldDispatch = true
            GhosttyPerf.event("wakeupScheduled")
        case .scheduled:
            shouldDispatch = false
            GhosttyPerf.event("wakeupCoalesced")
        case .running:
            needsAnotherRun = true
            shouldDispatch = false
            GhosttyPerf.event("wakeupDuringTick")
        }
        lock.unlock()

        guard shouldDispatch else { return }
        dispatch { [weak self] in
            self?.run(action)
        }
    }

    @MainActor
    private func run(_ action: @escaping @MainActor () -> Void) {
        let signpostID = GhosttyPerf.begin("tickSchedulerRun")
        defer { GhosttyPerf.end("tickSchedulerRun", signpostID) }

        lock.lock()
        state = .running
        lock.unlock()

        while true {
            action()

            lock.lock()
            if needsAnotherRun {
                needsAnotherRun = false
                lock.unlock()
                GhosttyPerf.event("tickSchedulerRerun")
                continue
            }

            state = .idle
            lock.unlock()
            return
        }
    }

    private static func dispatchOnMain(_ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                action()
            }
        }
    }
}
