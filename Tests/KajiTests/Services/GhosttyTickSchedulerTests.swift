import Testing

@testable import Kaji

@Suite("GhosttyTickScheduler")
@MainActor
struct GhosttyTickSchedulerTests {
    @Test("coalesces multiple wakeups before the main run")
    func coalescesScheduledWakeups() {
        var queued: [@MainActor () -> Void] = []
        let scheduler = GhosttyTickScheduler { action in
            queued.append(action)
        }
        var runs = 0

        scheduler.schedule {
            runs += 1
        }

        scheduler.schedule {
            runs += 1
        }

        #expect(queued.count == 1)
        queued.removeFirst()()
        #expect(runs == 1)
    }

    @Test("runs one more tick when a wakeup arrives during execution")
    func rerunsWhenWakeupArrivesDuringExecution() {
        var queued: [@MainActor () -> Void] = []
        let scheduler = GhosttyTickScheduler { action in
            queued.append(action)
        }
        let probe = ReentryProbe(scheduler: scheduler)

        scheduler.schedule {
            probe.run()
        }

        #expect(queued.count == 1)
        queued.removeFirst()()
        #expect(probe.runs == 2)
        #expect(queued.isEmpty)
    }
}

@MainActor
private final class ReentryProbe {
    let scheduler: GhosttyTickScheduler
    var runs = 0

    init(scheduler: GhosttyTickScheduler) {
        self.scheduler = scheduler
    }

    func run() {
        runs += 1
        if runs == 1 {
            scheduler.schedule {
                self.run()
            }
        }
    }
}
