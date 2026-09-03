import Foundation

enum MeetingTranscriptionProviderEventChannelError: Error, Equatable {
    case capacityExceeded

    var isRetryable: Bool { true }
}

final class MeetingTranscriptionProviderEventChannel: @unchecked Sendable {
    let events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>

    private let storage: MeetingTranscriptionProviderEventChannelStorage

    init(capacity: Int = MeetingTranscriptionBufferPolicy.maximumProviderEvents) {
        let storage = MeetingTranscriptionProviderEventChannelStorage(capacity: capacity)
        self.storage = storage
        events = AsyncThrowingStream(unfolding: { try await storage.next() })
    }

    func send(_ event: MeetingTranscriptionProviderEvent) {
        storage.send(event)
    }

    func finish() {
        storage.finish()
    }
}

private final class MeetingTranscriptionProviderEventChannelStorage: @unchecked Sendable {
    private typealias Result = Swift.Result<MeetingTranscriptionProviderEvent?, any Error>

    private let capacity: Int
    private let lock = NSLock()
    private var queue: [MeetingTranscriptionProviderEvent] = []
    private var waiter: CheckedContinuation<Result, Never>?
    private var terminalResult: Result?

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func next() async throws -> MeetingTranscriptionProviderEvent? {
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let immediate = lock.withLock { () -> Result? in
                    if !queue.isEmpty {
                        return .success(queue.removeFirst())
                    }
                    if let terminalResult {
                        return terminalResult
                    }
                    guard waiter == nil else {
                        return .failure(MeetingTranscriptionProviderEventChannelError.capacityExceeded)
                    }
                    waiter = continuation
                    return nil
                }
                if let immediate {
                    continuation.resume(returning: immediate)
                }
            }
        } onCancel: {
            cancel()
        }
        return try result.get()
    }

    func send(_ event: MeetingTranscriptionProviderEvent) {
        var resumedWaiter: CheckedContinuation<Result, Never>?
        var result: Result?
        lock.withLock {
            guard terminalResult == nil else { return }
            if let waiter {
                self.waiter = nil
                resumedWaiter = waiter
                result = .success(event)
                return
            }
            if queue.count < capacity {
                queue.append(event)
                return
            }
            if coalesce(event) {
                return
            }
            if evictOldestRevision() {
                queue.append(event)
                return
            }
            terminalResult = .failure(MeetingTranscriptionProviderEventChannelError.capacityExceeded)
        }
        if let resumedWaiter, let result {
            resumedWaiter.resume(returning: result)
        }
    }

    func finish() {
        terminate(with: .success(nil))
    }

    func cancel() {
        terminate(with: .failure(CancellationError()))
    }

    private func terminate(with result: Result) {
        let resumedWaiter = lock.withLock { () -> CheckedContinuation<Result, Never>? in
            guard terminalResult == nil else { return nil }
            terminalResult = result
            guard queue.isEmpty else { return nil }
            defer { waiter = nil }
            return waiter
        }
        resumedWaiter?.resume(returning: result)
    }

    private func coalesce(_ event: MeetingTranscriptionProviderEvent) -> Bool {
        guard let identity = revisionIdentity(event) else { return false }
        let matchingIndexes = queue.indices.filter { revisionIdentity(queue[$0]) == identity }
        guard let insertionIndex = matchingIndexes.first else { return false }
        for index in matchingIndexes.reversed() {
            queue.remove(at: index)
        }
        queue.insert(latestPartial(event), at: min(insertionIndex, queue.count))
        return true
    }

    private func evictOldestRevision() -> Bool {
        guard let firstIndex = queue.firstIndex(where: { revisionIdentity($0) != nil }),
              let identity = revisionIdentity(queue[firstIndex])
        else {
            return false
        }
        queue.removeAll { revisionIdentity($0) == identity }
        return true
    }

    private func revisionIdentity(_ event: MeetingTranscriptionProviderEvent) -> UUID? {
        switch event {
        case let .partial(value): value.utterance.id
        case let .replacement(value): value.utterance.id
        default: nil
        }
    }

    private func latestPartial(_ event: MeetingTranscriptionProviderEvent) -> MeetingTranscriptionProviderEvent {
        switch event {
        case .partial:
            event
        case let .replacement(value):
            .partial(MeetingTranscriptionPartialEvent(context: value.context, utterance: value.utterance))
        default:
            event
        }
    }
}
