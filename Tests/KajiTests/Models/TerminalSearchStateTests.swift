import Testing

@testable import Kaji

@Suite("TerminalSearchState")
@MainActor
struct TerminalSearchStateTests {
    @Test("short queries wait before publishing")
    func shortQueryDelay() async throws {
        let delay = ManualTerminalSearchDelay()
        let state = TerminalSearchState(delay: delay.sleep)
        var values: [String] = []
        let publications = ManualTerminalSearchPublications()
        state.startPublishing {
            values.append($0)
            publications.record()
        }

        state.needle = "ab"
        state.pushNeedle()

        await delay.waitForSleep()
        #expect(values.isEmpty)
        #expect(delay.durations == [.milliseconds(300)])

        delay.resumeNext()
        await publications.waitForPublish()
        #expect(values == ["ab"])
    }

    @Test("rapid long queries coalesce to the latest value")
    func longQueryCoalescing() async throws {
        let delay = ManualTerminalSearchDelay()
        let state = TerminalSearchState(delay: delay.sleep)
        var values: [String] = []
        let publications = ManualTerminalSearchPublications()
        state.startPublishing {
            values.append($0)
            publications.record()
        }

        state.needle = "hel"
        state.pushNeedle()
        await delay.waitForSleep()

        state.needle = "hello"
        state.pushNeedle()
        await delay.waitForSleep(count: 2)

        #expect(delay.durations == [.milliseconds(120), .milliseconds(120)])

        delay.resumeAll()
        await publications.waitForPublish()
        #expect(values == ["hello"])
    }
}

@MainActor
private final class ManualTerminalSearchPublications {
    private var count = 0
    private var waiter: CheckedContinuation<Void, Never>?

    func record() {
        count += 1
        waiter?.resume()
        waiter = nil
    }

    func waitForPublish(count expectedCount: Int = 1) async {
        guard count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }
}

@MainActor
private final class ManualTerminalSearchDelay {
    private(set) var durations: [Duration] = []
    private var sleepers: [CheckedContinuation<Void, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async {
        durations.append(duration)
        resumeReadyWaiters()
        await withCheckedContinuation { continuation in
            sleepers.append(continuation)
        }
    }

    func waitForSleep(count: Int = 1) async {
        guard sleepers.count < count else { return }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func resumeNext() {
        guard !sleepers.isEmpty else { return }
        sleepers.removeFirst().resume()
    }

    func resumeAll() {
        let currentSleepers = sleepers
        sleepers.removeAll()
        currentSleepers.forEach { $0.resume() }
    }

    private func resumeReadyWaiters() {
        let readyWaiters = waiters
        waiters.removeAll()
        readyWaiters.forEach { $0.resume() }
    }
}
