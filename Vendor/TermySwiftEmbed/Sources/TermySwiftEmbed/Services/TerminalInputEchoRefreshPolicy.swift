struct TerminalInputEchoRefreshPolicy: Equatable {
    private(set) var latestInputGeneration: UInt64 = 0
    private(set) var completedInputGeneration: UInt64 = 0
    private(set) var emptyPollCount = 0
    var maxEmptyPollCount = 48

    var hasPendingInput: Bool {
        latestInputGeneration != completedInputGeneration
    }

    var pendingInputGenerationForRefresh: UInt64? {
        hasPendingInput ? latestInputGeneration : nil
    }

    mutating func noteInput() -> UInt64 {
        latestInputGeneration &+= 1
        emptyPollCount = 0
        return latestInputGeneration
    }

    func acceptsWakeup(cadence: RefreshCadence) -> Bool {
        cadence != .active || hasPendingInput
    }

    func acceptsWakeup(cadence: RefreshCadence, isSuspended: Bool) -> Bool {
        isSuspended || acceptsWakeup(cadence: cadence)
    }

    func activeInputGenerationForWakeup(cadence: RefreshCadence) -> UInt64? {
        guard cadence == .active, hasPendingInput else {
            return nil
        }
        return latestInputGeneration
    }

    @discardableResult
    mutating func recordPoll(upTo generation: UInt64, observedFrameActivity: Bool) -> Bool {
        guard hasPendingInput else {
            emptyPollCount = 0
            return false
        }
        guard observedFrameActivity else {
            guard generation >= latestInputGeneration else {
                return false
            }
            emptyPollCount += 1
            guard emptyPollCount >= maxEmptyPollCount else {
                return false
            }
            completePoll(upTo: generation)
            return true
        }
        completePoll(upTo: generation)
        return true
    }

    private mutating func completePoll(upTo generation: UInt64) {
        let boundedGeneration = min(generation, latestInputGeneration)
        completedInputGeneration = max(completedInputGeneration, boundedGeneration)
        if !hasPendingInput {
            emptyPollCount = 0
        }
    }

    mutating func reset() {
        latestInputGeneration = 0
        completedInputGeneration = 0
        emptyPollCount = 0
    }
}
