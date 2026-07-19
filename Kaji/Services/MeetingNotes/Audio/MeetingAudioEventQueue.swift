import Foundation
import os

enum MeetingAudioQueueError: Error, Equatable {
    case invalidCapacity
    case multipleConsumers
}

struct MeetingAudioQueueMetrics: Equatable {
    let retainedEventCount: Int
    let retainedAudioBufferCount: Int
    let peakRetainedEventCount: Int
    let peakRetainedAudioBufferCount: Int
}

actor MeetingAudioEventQueue {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<MeetingAudioQueueEvent?, Error>
    }

    private let eventCapacity: Int
    private var events: [MeetingAudioQueueEvent] = []
    private var waiter: Waiter?
    private var isFinished = false
    private var peakRetainedEventCount = 0
    private var peakRetainedAudioBufferCount = 0

    init(eventCapacity: Int) throws {
        guard eventCapacity > 0 else { throw MeetingAudioQueueError.invalidCapacity }
        self.eventCapacity = eventCapacity
    }

    init(audioCapacity: Int) throws {
        try self.init(eventCapacity: audioCapacity)
    }

    func enqueue(_ buffer: MeetingOwnedAudioBuffer) {
        enqueue(.audio(buffer))
    }

    func enqueue(_ gap: MeetingAudioGap) {
        enqueue(.gap(gap))
    }

    func enqueueFailure(_ failure: MeetingAudioCaptureFailure) {
        enqueue(.failure(failure))
    }

    func enqueue(_ event: MeetingAudioQueueEvent) {
        guard !isFinished else { return }
        if let waiter {
            self.waiter = nil
            waiter.continuation.resume(returning: event)
            return
        }
        if case let .audio(buffer) = event {
            let metadataReserve = min(eventCapacity - 1, min(8, max(1, eventCapacity / 8)))
            let audioLimit = eventCapacity - metadataReserve
            if retainedAudioBufferCount >= audioLimit {
                let gap = MeetingAudioGap(buffer: buffer, reason: .backpressure)
                if coalesce(.gap(gap)) {
                    updatePeaks()
                    return
                }
                if events.count < eventCapacity {
                    events.append(.gap(gap))
                } else {
                    retainGap(gap)
                }
                updatePeaks()
                return
            }
        }
        if coalesce(event) {
            updatePeaks()
            return
        }
        if events.count < eventCapacity {
            events.append(event)
            updatePeaks()
            return
        }
        retainOverflow(event)
        updatePeaks()
    }

    func next() async throws -> MeetingAudioQueueEvent? {
        try Task.checkCancellation()
        if !events.isEmpty { return events.removeFirst() }
        if isFinished { return nil }
        guard waiter == nil else { throw MeetingAudioQueueError.multipleConsumers }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiter = Waiter(id: id, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        guard events.isEmpty, let waiter else { return }
        self.waiter = nil
        waiter.continuation.resume(returning: nil)
    }

    func cancel() {
        isFinished = true
        events.removeAll(keepingCapacity: false)
        guard let waiter else { return }
        self.waiter = nil
        waiter.continuation.resume(throwing: CancellationError())
    }

    func metrics() -> MeetingAudioQueueMetrics {
        MeetingAudioQueueMetrics(
            retainedEventCount: events.count,
            retainedAudioBufferCount: retainedAudioBufferCount,
            peakRetainedEventCount: peakRetainedEventCount,
            peakRetainedAudioBufferCount: peakRetainedAudioBufferCount
        )
    }

    private var retainedAudioBufferCount: Int {
        events.reduce(into: 0) { count, event in
            if case .audio = event { count += 1 }
        }
    }

    private func coalesce(_ event: MeetingAudioQueueEvent) -> Bool {
        switch event {
        case let .gap(gap):
            guard let index = coalescibleGapIndex(for: gap, in: events),
                  case var .gap(existing) = events[index]
            else {
                return false
            }
            existing.merge(gap)
            events[index] = .gap(existing)
            return true
        case let .failure(failure):
            guard let index = events.lastIndex(where: {
                guard case let .failure(existing) = $0 else { return false }
                return existing.domain == failure.domain &&
                    existing.code == failure.code &&
                    existing.message == failure.message &&
                    existing.source == failure.source
            }), case let .failure(existing) = events[index]
            else {
                return false
            }
            events[index] = .failure(existing.merging(failure))
            return true
        case .audio:
            return false
        }
    }

    private func retainOverflow(_ event: MeetingAudioQueueEvent) {
        switch event {
        case let .audio(buffer):
            retainGap(MeetingAudioGap(buffer: buffer, reason: .backpressure))
        case let .gap(gap):
            retainGap(gap)
        case let .failure(failure):
            if let index = events.lastIndex(where: {
                if case .failure = $0 { return true }
                return false
            }), case let .failure(existing) = events[index] {
                events[index] = .failure(existing.merging(failure))
                return
            }
        }
    }

    private func retainGap(_ gap: MeetingAudioGap) {
        if coalesce(.gap(gap)) { return }
        if let index = events.lastIndex(where: {
            if case .failure = $0 { return true }
            return false
        }) {
            events[index] = .gap(gap)
            return
        }
        if let index = events.lastIndex(where: {
            guard case let .audio(buffer) = $0 else { return false }
            return buffer.source == gap.source
        }), case let .audio(buffer) = events[index] {
            var replacement = MeetingAudioGap(buffer: buffer, reason: .backpressure)
            replacement.merge(gap)
            events[index] = .gap(replacement)
            return
        }
        if let index = events.lastIndex(where: {
            guard case let .audio(buffer) = $0 else { return false }
            return coalescibleGapIndex(
                for: MeetingAudioGap(buffer: buffer, reason: .backpressure),
                in: events
            ) != nil
        }), case let .audio(buffer) = events[index] {
            _ = coalesce(.gap(MeetingAudioGap(buffer: buffer, reason: .backpressure)))
            events[index] = .gap(gap)
        }
    }

    private func coalescibleGapIndex(
        for gap: MeetingAudioGap,
        in events: [MeetingAudioQueueEvent]
    ) -> Int? {
        for index in events.indices.reversed() {
            switch events[index] {
            case let .gap(existing) where existing.source == gap.source:
                return existing.reason == gap.reason ? index : nil
            default:
                continue
            }
        }
        return nil
    }

    private func updatePeaks() {
        peakRetainedEventCount = max(peakRetainedEventCount, events.count)
        peakRetainedAudioBufferCount = max(peakRetainedAudioBufferCount, retainedAudioBufferCount)
    }

    private func cancelWaiter(id: UUID) {
        guard waiter?.id == id else { return }
        let continuation = waiter?.continuation
        waiter = nil
        continuation?.resume(throwing: CancellationError())
    }
}

enum MeetingAudioIngressDisposition: Equatable {
    case accepted
    case dropped
    case closed
}

struct MeetingAudioIngressSubmission: Equatable {
    let disposition: MeetingAudioIngressDisposition
    let submissionNumber: UInt64?
}

struct MeetingAudioIngressMetrics: Equatable {
    let retainedEventCount: Int
    let retainedAudioBufferCount: Int
    let peakRetainedEventCount: Int
    let peakRetainedAudioBufferCount: Int
    let drainTaskCount: Int
}

final class MeetingAudioQueueIngress: Sendable {
    private enum Lifecycle: Equatable {
        case open
        case finishing
        case cancelled
    }

    private struct State {
        var events: [MeetingAudioQueueEvent] = []
        var lifecycle = Lifecycle.open
        var wakeContinuation: CheckedContinuation<Void, Never>?
        var nextSubmissionNumber: UInt64 = 0
        var peakRetainedEventCount = 0
        var peakRetainedAudioBufferCount = 0
    }

    private final class Storage: Sendable {
        let capacity: Int
        let lock = OSAllocatedUnfairLock(initialState: State())

        init(capacity: Int) {
            self.capacity = capacity
        }
    }

    private let queue: MeetingAudioEventQueue
    private let storage: Storage
    private let drainTask: Task<Void, Never>

    convenience init(queue: MeetingAudioEventQueue) {
        self.init(validatedQueue: queue, pendingEventCapacity: 256)
    }

    init(queue: MeetingAudioEventQueue, pendingEventCapacity: Int) throws {
        guard pendingEventCapacity > 1 else { throw MeetingAudioQueueError.invalidCapacity }
        self.queue = queue
        storage = Storage(capacity: pendingEventCapacity)
        let storage = storage
        drainTask = Task.detached(priority: .userInitiated) {
            await Self.drain(storage: storage, queue: queue)
        }
    }

    private init(validatedQueue queue: MeetingAudioEventQueue, pendingEventCapacity: Int) {
        self.queue = queue
        storage = Storage(capacity: pendingEventCapacity)
        let storage = storage
        drainTask = Task.detached(priority: .userInitiated) {
            await Self.drain(storage: storage, queue: queue)
        }
    }

    @discardableResult
    func submit(_ buffer: MeetingOwnedAudioBuffer) -> MeetingAudioIngressSubmission {
        submit(.audio(buffer))
    }

    @discardableResult
    func submit(_ gap: MeetingAudioGap) -> MeetingAudioIngressSubmission {
        submit(.gap(gap))
    }

    @discardableResult
    func submit(_ failure: MeetingAudioCaptureFailure) -> MeetingAudioIngressSubmission {
        submit(.failure(failure))
    }

    func finish() async {
        let continuation = storage.lock.withLock { state -> CheckedContinuation<Void, Never>? in
            guard state.lifecycle == .open else { return nil }
            state.lifecycle = .finishing
            let continuation = state.wakeContinuation
            state.wakeContinuation = nil
            return continuation
        }
        continuation?.resume()
        await drainTask.value
    }

    func cancel() async {
        let continuation = storage.lock.withLock { state -> CheckedContinuation<Void, Never>? in
            state.lifecycle = .cancelled
            state.events.removeAll(keepingCapacity: false)
            let continuation = state.wakeContinuation
            state.wakeContinuation = nil
            return continuation
        }
        continuation?.resume()
        drainTask.cancel()
        await queue.cancel()
        await drainTask.value
    }

    func metrics() -> MeetingAudioIngressMetrics {
        storage.lock.withLock { state in
            MeetingAudioIngressMetrics(
                retainedEventCount: state.events.count,
                retainedAudioBufferCount: Self.audioCount(state.events),
                peakRetainedEventCount: state.peakRetainedEventCount,
                peakRetainedAudioBufferCount: state.peakRetainedAudioBufferCount,
                drainTaskCount: 1
            )
        }
    }

    private func submit(_ event: MeetingAudioQueueEvent) -> MeetingAudioIngressSubmission {
        let result = storage.lock.withLock { state -> (
            MeetingAudioIngressSubmission,
            CheckedContinuation<Void, Never>?
        ) in
            guard state.lifecycle == .open else {
                return (
                    MeetingAudioIngressSubmission(disposition: .closed, submissionNumber: nil),
                    nil
                )
            }
            let submissionNumber = state.nextSubmissionNumber
            state.nextSubmissionNumber &+= 1
            let disposition = Self.admit(event, state: &state, capacity: storage.capacity)
            state.peakRetainedEventCount = max(state.peakRetainedEventCount, state.events.count)
            state.peakRetainedAudioBufferCount = max(
                state.peakRetainedAudioBufferCount,
                Self.audioCount(state.events)
            )
            let continuation = state.wakeContinuation
            state.wakeContinuation = nil
            return (
                MeetingAudioIngressSubmission(
                    disposition: disposition,
                    submissionNumber: submissionNumber
                ),
                continuation
            )
        }
        result.1?.resume()
        return result.0
    }

    private static func admit(
        _ event: MeetingAudioQueueEvent,
        state: inout State,
        capacity: Int
    ) -> MeetingAudioIngressDisposition {
        if case let .audio(buffer) = event {
            let gap = MeetingAudioGap(buffer: buffer, reason: .backpressure)
            if coalesce(.gap(gap), into: &state.events) { return .dropped }
            let metadataReserve = min(8, max(1, capacity / 8))
            let audioLimit = capacity - metadataReserve
            if audioCount(state.events) >= audioLimit {
                if state.events.count < capacity {
                    state.events.append(.gap(gap))
                } else {
                    retainGap(gap, in: &state.events)
                }
                return .dropped
            }
        } else if coalesce(event, into: &state.events) {
            return .accepted
        }
        guard state.events.count < capacity else {
            switch event {
            case let .audio(buffer):
                retainGap(MeetingAudioGap(buffer: buffer, reason: .backpressure), in: &state.events)
            case let .gap(gap):
                retainGap(gap, in: &state.events)
            case let .failure(failure):
                if let index = state.events.lastIndex(where: {
                    if case .failure = $0 { return true }
                    return false
                }), case let .failure(existing) = state.events[index] {
                    state.events[index] = .failure(existing.merging(failure))
                }
            }
            return .dropped
        }
        state.events.append(event)
        return .accepted
    }

    private static func coalesce(
        _ event: MeetingAudioQueueEvent,
        into events: inout [MeetingAudioQueueEvent]
    ) -> Bool {
        switch event {
        case let .gap(gap):
            guard let index = coalescibleGapIndex(for: gap, in: events),
                  case var .gap(existing) = events[index]
            else {
                return false
            }
            existing.merge(gap)
            events[index] = .gap(existing)
            return true
        case let .failure(failure):
            guard let index = events.lastIndex(where: {
                guard case let .failure(existing) = $0 else { return false }
                return existing.domain == failure.domain &&
                    existing.code == failure.code &&
                    existing.message == failure.message &&
                    existing.source == failure.source
            }), case let .failure(existing) = events[index]
            else {
                return false
            }
            events[index] = .failure(existing.merging(failure))
            return true
        case .audio:
            return false
        }
    }

    private static func coalescibleGapIndex(
        for gap: MeetingAudioGap,
        in events: [MeetingAudioQueueEvent]
    ) -> Int? {
        for index in events.indices.reversed() {
            switch events[index] {
            case let .gap(existing) where existing.source == gap.source:
                return existing.reason == gap.reason ? index : nil
            default:
                continue
            }
        }
        return nil
    }

    private static func retainGap(
        _ gap: MeetingAudioGap,
        in events: inout [MeetingAudioQueueEvent]
    ) {
        if coalesce(.gap(gap), into: &events) { return }
        if let index = events.lastIndex(where: {
            guard case let .audio(buffer) = $0 else { return false }
            return buffer.source == gap.source
        }), case let .audio(buffer) = events[index] {
            var replacement = MeetingAudioGap(buffer: buffer, reason: .backpressure)
            replacement.merge(gap)
            events[index] = .gap(replacement)
            return
        }
        if let index = events.lastIndex(where: {
            if case .failure = $0 { return true }
            return false
        }) {
            events[index] = .gap(gap)
            return
        }
        if let index = events.lastIndex(where: {
            guard case let .audio(buffer) = $0 else { return false }
            return coalescibleGapIndex(
                for: MeetingAudioGap(buffer: buffer, reason: .backpressure),
                in: events
            ) != nil
        }), case let .audio(buffer) = events[index] {
            _ = coalesce(.gap(MeetingAudioGap(buffer: buffer, reason: .backpressure)), into: &events)
            events[index] = .gap(gap)
        }
    }

    private static func drain(storage: Storage, queue: MeetingAudioEventQueue) async {
        while let event = await nextEvent(storage: storage) {
            await queue.enqueue(event)
        }
        let shouldFinish = storage.lock.withLock { $0.lifecycle == .finishing }
        if shouldFinish {
            await queue.finish()
        }
    }

    private static func nextEvent(storage: Storage) async -> MeetingAudioQueueEvent? {
        while true {
            let event = storage.lock.withLock { state -> MeetingAudioQueueEvent? in
                guard !state.events.isEmpty else { return nil }
                return state.events.removeFirst()
            }
            if let event { return event }
            let shouldStop = storage.lock.withLock { $0.lifecycle != .open }
            if shouldStop { return nil }
            await withCheckedContinuation { continuation in
                let shouldResume = storage.lock.withLock { state -> Bool in
                    if !state.events.isEmpty || state.lifecycle != .open { return true }
                    state.wakeContinuation = continuation
                    return false
                }
                if shouldResume { continuation.resume() }
            }
        }
    }

    private static func audioCount(_ events: [MeetingAudioQueueEvent]) -> Int {
        events.reduce(into: 0) { count, event in
            if case .audio = event { count += 1 }
        }
    }
}
