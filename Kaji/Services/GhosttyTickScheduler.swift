import AppKit

final class GhosttyTickScheduler: @unchecked Sendable {
    typealias Dispatcher = (@escaping @MainActor () -> Void, TimeInterval) -> Void

    private enum State {
        case idle
        case scheduled
        case running
    }

    private let lock = NSLock()
    private let dispatch: Dispatcher
    private let policyProvider: @Sendable () -> GhosttyTickSchedulerPolicy
    private var state: State = .idle
    private var needsAnotherRun = false
    private var lastRunDate = Date.distantPast

    init(
        dispatch: @escaping Dispatcher = GhosttyTickScheduler.dispatchOnMain,
        policyProvider: @escaping @Sendable () -> GhosttyTickSchedulerPolicy = { GhosttyTickSchedulerPolicyStore.shared.policy }
    ) {
        self.dispatch = dispatch
        self.policyProvider = policyProvider
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        let shouldDispatch: Bool
        let delay: TimeInterval

        lock.lock()
        switch state {
        case .idle:
            state = .scheduled
            shouldDispatch = true
            delay = policyProvider().delay(after: lastRunDate)
            GhosttyPerf.event("wakeupScheduled")
        case .scheduled:
            shouldDispatch = false
            delay = 0
            GhosttyPerf.event("wakeupCoalesced")
        case .running:
            needsAnotherRun = true
            shouldDispatch = false
            delay = 0
            GhosttyPerf.event("wakeupDuringTick")
        }
        lock.unlock()

        guard shouldDispatch else { return }
        dispatch({ [weak self] in
            self?.run(action)
        }, delay)
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

            lastRunDate = Date()
            state = .idle
            lock.unlock()
            return
        }
    }

    private static func dispatchOnMain(_ action: @escaping @MainActor () -> Void, delay: TimeInterval) {
        if delay <= 0 {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    action()
                }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                action()
            }
        }
    }
}
