import Foundation

enum STTWebSocketMessage: Equatable {
    case text(String)
    case binary(Data)

    var byteCount: Int {
        switch self {
        case let .text(value):
            value.utf8.count
        case let .binary(value):
            value.count
        }
    }
}

enum STTWebSocketState: Equatable {
    case disconnected
    case connecting
    case open
    case closing
}

enum STTWebSocketEvent: Equatable {
    case stateChanged(STTWebSocketState)
    case message(STTWebSocketMessage)
    case pong
    case closed(code: Int?)
    case failed(STTNetworkError)
}

struct STTWebSocketPolicy: Equatable {
    let maximumOutboundMessageBytes: Int
    let maximumInboundMessageBytes: Int
    let maximumPendingSends: Int
    let maximumBufferedEventCount: Int
    let maximumBufferedEventBytes: Int
    let openTimeout: TimeInterval
    let sendTimeout: TimeInterval
    let drainTimeout: TimeInterval
    let closeTimeout: TimeInterval

    init(
        maximumOutboundMessageBytes: Int = 1024 * 1024,
        maximumInboundMessageBytes: Int = 4 * 1024 * 1024,
        maximumPendingSends: Int = 8,
        maximumBufferedEventCount: Int = 16,
        maximumBufferedEventBytes: Int = 8 * 1024 * 1024,
        openTimeout: TimeInterval = 15,
        sendTimeout: TimeInterval = 15,
        drainTimeout: TimeInterval = 5,
        closeTimeout: TimeInterval = 5
    ) throws {
        guard maximumOutboundMessageBytes >= 1,
              maximumOutboundMessageBytes <= 16 * 1024 * 1024,
              maximumInboundMessageBytes >= 1,
              maximumInboundMessageBytes <= 16 * 1024 * 1024,
              maximumPendingSends >= 1,
              maximumPendingSends <= 64,
              maximumBufferedEventCount >= 1,
              maximumBufferedEventCount <= 64,
              maximumBufferedEventBytes >= maximumInboundMessageBytes,
              maximumBufferedEventBytes <= 64 * 1024 * 1024,
              Self.isValidTimeout(openTimeout),
              Self.isValidTimeout(sendTimeout),
              Self.isValidTimeout(drainTimeout),
              Self.isValidTimeout(closeTimeout)
        else {
            throw STTNetworkError.invalidConfiguration
        }
        self.maximumOutboundMessageBytes = maximumOutboundMessageBytes
        self.maximumInboundMessageBytes = maximumInboundMessageBytes
        self.maximumPendingSends = maximumPendingSends
        self.maximumBufferedEventCount = maximumBufferedEventCount
        self.maximumBufferedEventBytes = maximumBufferedEventBytes
        self.openTimeout = openTimeout
        self.sendTimeout = sendTimeout
        self.drainTimeout = drainTimeout
        self.closeTimeout = closeTimeout
    }

    private static func isValidTimeout(_ value: TimeInterval) -> Bool {
        value.isFinite && value >= 0.1 && value <= 300
    }
}

protocol STTWebSocketTransporting: Sendable {
    func events() async -> AsyncStream<STTWebSocketEvent>
    func currentState() async -> STTWebSocketState
    func connect(request: URLRequest) async throws
    func send(_ message: STTWebSocketMessage) async throws
    func ping() async throws
    func close(code: Int, reason: String?) async throws
    func cancel() async
}

protocol STTWebSocketTransportFactory: Sendable {
    func makeTransport() -> any STTWebSocketTransporting
}

protocol STTWebSocketTasking: AnyObject, Sendable {
    var closeCode: Int? { get }
    func resume()
    func send(_ message: STTWebSocketMessage) async throws
    func receive() async throws -> STTWebSocketMessage
    func ping() async throws
    func cancel(code: Int, reason: Data?)
}

protocol STTWebSocketTaskFactory: Sendable {
    func makeTask(request: URLRequest) -> any STTWebSocketTasking
}

final class URLSessionSTTWebSocketTask: STTWebSocketTasking, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    let configuredMaximumMessageSize: Int

    init(task: URLSessionWebSocketTask, maximumMessageSize: Int) {
        self.task = task
        configuredMaximumMessageSize = maximumMessageSize
        task.maximumMessageSize = maximumMessageSize
    }

    var closeCode: Int? {
        let value = task.closeCode.rawValue
        return value == 0 ? nil : value
    }

    func resume() {
        task.resume()
    }

    func send(_ message: STTWebSocketMessage) async throws {
        switch message {
        case let .text(value):
            try await task.send(.string(value))
        case let .binary(value):
            try await task.send(.data(value))
        }
    }

    func receive() async throws -> STTWebSocketMessage {
        switch try await task.receive() {
        case let .string(value):
            return .text(value)
        case let .data(value):
            return .binary(value)
        @unknown default:
            throw STTNetworkError.protocolViolation
        }
    }

    func ping() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func cancel(code: Int, reason: Data?) {
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .goingAway
        task.cancel(with: closeCode, reason: reason)
    }
}

final class STTWebSocketRedirectDenyingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

final class URLSessionSTTWebSocketTaskFactory: STTWebSocketTaskFactory, @unchecked Sendable {
    private let delegate: STTWebSocketRedirectDenyingDelegate
    private let session: URLSession
    private let maximumMessageSize: Int

    init(configuration: URLSessionConfiguration, maximumMessageSize: Int) {
        let delegate = STTWebSocketRedirectDenyingDelegate()
        self.delegate = delegate
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.maximumMessageSize = maximumMessageSize
    }

    func makeTask(request: URLRequest) -> any STTWebSocketTasking {
        URLSessionSTTWebSocketTask(
            task: session.webSocketTask(with: request),
            maximumMessageSize: maximumMessageSize
        )
    }

    deinit {
        session.invalidateAndCancel()
    }
}

struct URLSessionSTTWebSocketTransportFactory: STTWebSocketTransportFactory {
    let taskFactory: any STTWebSocketTaskFactory
    let policy: STTWebSocketPolicy

    init(sessionPolicy: STTURLSessionPolicy, webSocketPolicy: STTWebSocketPolicy) {
        taskFactory = URLSessionSTTWebSocketTaskFactory(
            configuration: STTURLSessionConfigurationFactory.makeEphemeral(policy: sessionPolicy),
            maximumMessageSize: webSocketPolicy.maximumInboundMessageBytes
        )
        policy = webSocketPolicy
    }

    func makeTransport() -> any STTWebSocketTransporting {
        URLSessionSTTWebSocketTransport(taskFactory: taskFactory, policy: policy)
    }
}

struct PolicyEnforcingSTTWebSocketTransportFactory: STTWebSocketTransportFactory {
    let underlying: any STTWebSocketTransportFactory
    let endpointPolicy: STTEndpointPolicy

    func makeTransport() -> any STTWebSocketTransporting {
        PolicyEnforcingSTTWebSocketTransport(
            underlying: underlying.makeTransport(),
            endpointPolicy: endpointPolicy
        )
    }
}

private actor PolicyEnforcingSTTWebSocketTransport: STTWebSocketTransporting {
    private let underlying: any STTWebSocketTransporting
    private let endpointPolicy: STTEndpointPolicy

    init(underlying: any STTWebSocketTransporting, endpointPolicy: STTEndpointPolicy) {
        self.underlying = underlying
        self.endpointPolicy = endpointPolicy
    }

    func events() async -> AsyncStream<STTWebSocketEvent> {
        await underlying.events()
    }

    func currentState() async -> STTWebSocketState {
        await underlying.currentState()
    }

    func connect(request: URLRequest) async throws {
        var request = request
        STTRequestSecurity.apply(to: &request)
        guard let url = request.url else { throw STTEndpointPolicyError.invalidEndpoint }
        try endpointPolicy.validate(url, trustMode: .builtIn)
        try await underlying.connect(request: request)
    }

    func send(_ message: STTWebSocketMessage) async throws {
        try await underlying.send(message)
    }

    func ping() async throws {
        try await underlying.ping()
    }

    func close(code: Int, reason: String?) async throws {
        try await underlying.close(code: code, reason: reason)
    }

    func cancel() async {
        await underlying.cancel()
    }
}

actor URLSessionSTTWebSocketTransport: STTWebSocketTransporting {
    private let taskFactory: any STTWebSocketTaskFactory
    private let policy: STTWebSocketPolicy
    private let eventStream: AsyncStream<STTWebSocketEvent>
    private let eventChannel: STTWebSocketEventChannel
    private var state = STTWebSocketState.disconnected
    private var task: (any STTWebSocketTasking)?
    private var receiveLoopTask: Task<Void, Never>?
    private var generation: UUID?
    private var pendingSendCount = 0

    init(taskFactory: any STTWebSocketTaskFactory, policy: STTWebSocketPolicy) {
        self.taskFactory = taskFactory
        self.policy = policy
        let eventChannel = STTWebSocketEventChannel(
            maximumMessageCount: policy.maximumBufferedEventCount,
            maximumMessageBytes: policy.maximumBufferedEventBytes
        )
        self.eventChannel = eventChannel
        eventStream = eventChannel.events
    }

    func events() -> AsyncStream<STTWebSocketEvent> {
        eventStream
    }

    func currentState() -> STTWebSocketState {
        state
    }

    func connect(request: URLRequest) async throws {
        guard state == .disconnected,
              let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "wss",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.fragment == nil
        else {
            throw STTNetworkError.protocolViolation
        }
        transition(to: .connecting)
        let nextGeneration = UUID()
        let nextTask = taskFactory.makeTask(request: request)
        generation = nextGeneration
        task = nextTask
        nextTask.resume()
        do {
            try await sttWithTimeout(seconds: policy.openTimeout) {
                try await nextTask.ping()
            }
            try Task.checkCancellation()
            guard generation == nextGeneration, state == .connecting else {
                throw STTNetworkError.cancelled
            }
            transition(to: .open)
            receiveLoopTask = Task { [weak self] in
                await self?.receiveLoop(task: nextTask, generation: nextGeneration)
            }
        } catch {
            nextTask.cancel(code: 1001, reason: nil)
            finish(generation: nextGeneration, error: STTNetworkRedactor.error(error), closeCode: nil)
            throw STTNetworkRedactor.error(error)
        }
    }

    func send(_ message: STTWebSocketMessage) async throws {
        guard state == .open, let task, let generation else {
            throw STTNetworkError.protocolViolation
        }
        guard message.byteCount <= policy.maximumOutboundMessageBytes else {
            throw STTNetworkError.responseTooLarge
        }
        guard pendingSendCount < policy.maximumPendingSends else {
            throw STTNetworkError.protocolViolation
        }
        pendingSendCount += 1
        defer { pendingSendCount -= 1 }
        do {
            try await sttWithTimeout(seconds: policy.sendTimeout) {
                try await task.send(message)
            }
        } catch {
            let sanitized = STTNetworkRedactor.error(error)
            task.cancel(code: 1011, reason: nil)
            finish(generation: generation, error: sanitized, closeCode: nil)
            throw sanitized
        }
    }

    func ping() async throws {
        guard state == .open, let task, let generation else {
            throw STTNetworkError.protocolViolation
        }
        do {
            try await sttWithTimeout(seconds: policy.sendTimeout) {
                try await task.ping()
            }
            guard self.generation == generation, state == .open else {
                throw STTNetworkError.cancelled
            }
            eventChannel.sendControl(.pong)
        } catch {
            let sanitized = STTNetworkRedactor.error(error)
            task.cancel(code: 1011, reason: nil)
            finish(generation: generation, error: sanitized, closeCode: nil)
            throw sanitized
        }
    }

    func close(code: Int = 1000, reason: String? = nil) async throws {
        guard state == .open || state == .connecting, let task, let generation else {
            if state == .disconnected { return }
            throw STTNetworkError.protocolViolation
        }
        guard code == 1000 || code == 1001 || (3000 ... 4999).contains(code) else {
            throw STTNetworkError.protocolViolation
        }
        transition(to: .closing)
        let drained = await waitForPendingSends()
        task.cancel(code: code, reason: sanitizedCloseReason(reason))
        let loop = receiveLoopTask
        do {
            if let loop {
                try await sttWithTimeout(seconds: policy.closeTimeout) {
                    await loop.value
                }
            }
        } catch {
            loop?.cancel()
            finish(generation: generation, error: nil, closeCode: task.closeCode ?? code)
            throw STTNetworkError.timedOut
        }
        finish(generation: generation, error: nil, closeCode: task.closeCode ?? code)
        guard drained else { throw STTNetworkError.timedOut }
    }

    func cancel() {
        guard let task, let generation else { return }
        task.cancel(code: 1001, reason: nil)
        receiveLoopTask?.cancel()
        finish(generation: generation, error: .cancelled, closeCode: nil)
    }

    private func receiveLoop(task: any STTWebSocketTasking, generation: UUID) async {
        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                guard self.generation == generation else { return }
                guard message.byteCount <= policy.maximumInboundMessageBytes else {
                    task.cancel(code: 1009, reason: nil)
                    finish(generation: generation, error: .responseTooLarge, closeCode: 1009)
                    return
                }
                if !eventChannel.sendMessage(message) {
                    task.cancel(code: 1009, reason: nil)
                    finish(generation: generation, error: .connectionFailed, closeCode: 1009)
                    return
                }
            }
        } catch {
            guard self.generation == generation else { return }
            if state == .closing || Task.isCancelled {
                finish(generation: generation, error: nil, closeCode: task.closeCode)
            } else {
                finish(
                    generation: generation,
                    error: STTNetworkRedactor.error(error),
                    closeCode: task.closeCode
                )
            }
        }
    }

    private func waitForPendingSends() async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(policy.drainTimeout))
        while pendingSendCount > 0, clock.now < deadline {
            try? await clock.sleep(for: .milliseconds(10))
        }
        return pendingSendCount == 0
    }

    private func sanitizedCloseReason(_ reason: String?) -> Data? {
        guard let reason else { return nil }
        let bytes = reason.utf8.filter { $0 >= 0x20 && $0 <= 0x7E }.prefix(123)
        return bytes.isEmpty ? nil : Data(bytes)
    }

    private func transition(to newState: STTWebSocketState) {
        state = newState
        eventChannel.sendControl(.stateChanged(newState))
    }

    private func finish(generation completedGeneration: UUID, error: STTNetworkError?, closeCode: Int?) {
        guard generation == completedGeneration else { return }
        task = nil
        generation = nil
        receiveLoopTask = nil
        pendingSendCount = 0
        if let error { eventChannel.sendControl(.failed(error)) }
        eventChannel.sendControl(.closed(code: closeCode))
        transition(to: .disconnected)
    }
}

private final class STTWebSocketEventChannel: @unchecked Sendable {
    let events: AsyncStream<STTWebSocketEvent>

    private let storage: STTWebSocketEventChannelStorage

    init(maximumMessageCount: Int, maximumMessageBytes: Int) {
        let storage = STTWebSocketEventChannelStorage(
            maximumMessageCount: maximumMessageCount,
            maximumMessageBytes: maximumMessageBytes
        )
        self.storage = storage
        events = AsyncStream(unfolding: { await storage.next() })
    }

    func sendMessage(_ message: STTWebSocketMessage) -> Bool {
        storage.send(.message(message), messageBytes: message.byteCount)
    }

    func sendControl(_ event: STTWebSocketEvent) {
        storage.sendControl(event)
    }
}

private final class STTWebSocketEventChannelStorage: @unchecked Sendable {
    private struct Entry {
        let event: STTWebSocketEvent
        let messageBytes: Int
    }

    private let maximumMessageCount: Int
    private let maximumMessageBytes: Int
    private let maximumControlCount = 8
    private let lock = NSLock()
    private var queue: [Entry] = []
    private var queuedMessageCount = 0
    private var queuedMessageBytes = 0
    private var queuedControlCount = 0
    private var waiter: CheckedContinuation<STTWebSocketEvent?, Never>?

    init(maximumMessageCount: Int, maximumMessageBytes: Int) {
        self.maximumMessageCount = maximumMessageCount
        self.maximumMessageBytes = maximumMessageBytes
    }

    func next() async -> STTWebSocketEvent? {
        await withCheckedContinuation { continuation in
            let immediate = lock.withLock { () -> STTWebSocketEvent? in
                guard !queue.isEmpty else {
                    waiter = continuation
                    return nil
                }
                let entry = queue.removeFirst()
                if entry.messageBytes > 0 {
                    queuedMessageCount -= 1
                    queuedMessageBytes -= entry.messageBytes
                } else {
                    queuedControlCount -= 1
                }
                return entry.event
            }
            if let immediate {
                continuation.resume(returning: immediate)
            }
        }
    }

    func send(_ event: STTWebSocketEvent, messageBytes: Int) -> Bool {
        var resumedWaiter: CheckedContinuation<STTWebSocketEvent?, Never>?
        let accepted = lock.withLock { () -> Bool in
            if let waiter {
                self.waiter = nil
                resumedWaiter = waiter
                return true
            }
            guard queuedMessageCount < maximumMessageCount,
                  messageBytes <= maximumMessageBytes - queuedMessageBytes
            else {
                return false
            }
            queue.append(Entry(event: event, messageBytes: messageBytes))
            queuedMessageCount += 1
            queuedMessageBytes += messageBytes
            return true
        }
        if accepted {
            resumedWaiter?.resume(returning: event)
        }
        return accepted
    }

    func sendControl(_ event: STTWebSocketEvent) {
        var resumedWaiter: CheckedContinuation<STTWebSocketEvent?, Never>?
        lock.withLock {
            if let waiter {
                self.waiter = nil
                resumedWaiter = waiter
                return
            }
            if queuedControlCount >= maximumControlCount {
                if case .pong = event, queue.contains(where: { $0.event == .pong }) { return }
                if case .stateChanged = event,
                   let index = queue.lastIndex(where: {
                       if case .stateChanged = $0.event { true } else { false }
                   })
                {
                    queue[index] = Entry(event: event, messageBytes: 0)
                    return
                }
                if let index = queue.firstIndex(where: { $0.event == .pong }) {
                    queue.remove(at: index)
                    queuedControlCount -= 1
                } else {
                    return
                }
            }
            queue.append(Entry(event: event, messageBytes: 0))
            queuedControlCount += 1
        }
        resumedWaiter?.resume(returning: event)
    }
}

private func sttWithTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = STTTimeoutRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.start(continuation: continuation, seconds: seconds, operation: operation)
        }
    } onCancel: {
        race.resolve(.failure(CancellationError()))
    }
}

private final class STTTimeoutRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var result: Result<Value, Error>?

    func start(
        continuation: CheckedContinuation<Value, Error>,
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> Value
    ) {
        lock.withLock { self.continuation = continuation }
        let operationTask = Task {
            do {
                try await resolve(.success(operation()))
            } catch {
                resolve(.failure(error))
            }
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: .seconds(seconds))
                resolve(.failure(STTNetworkError.timedOut))
            } catch {}
        }
        let pendingResult = lock.withLock { () -> Result<Value, Error>? in
            if result == nil {
                self.operationTask = operationTask
                self.timeoutTask = timeoutTask
                return nil
            }
            return result
        }
        if pendingResult != nil {
            operationTask.cancel()
            timeoutTask.cancel()
            resumeIfReady()
        }
    }

    func resolve(_ result: Result<Value, Error>) {
        let shouldResume = lock.withLock { () -> Bool in
            guard self.result == nil else { return false }
            self.result = result
            return true
        }
        if shouldResume { resumeIfReady() }
    }

    private func resumeIfReady() {
        let completion = lock.withLock { () -> STTTimeoutCompletion<Value>? in
            guard let continuation, let result else { return nil }
            self.continuation = nil
            let tasks = [operationTask, timeoutTask].compactMap(\.self)
            self.operationTask = nil
            self.timeoutTask = nil
            return STTTimeoutCompletion(continuation: continuation, result: result, tasks: tasks)
        }
        guard let completion else { return }
        completion.tasks.forEach { $0.cancel() }
        completion.continuation.resume(with: completion.result)
    }
}

private struct STTTimeoutCompletion<Value: Sendable> {
    let continuation: CheckedContinuation<Value, Error>
    let result: Result<Value, Error>
    let tasks: [Task<Void, Never>]
}
