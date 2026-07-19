import Foundation
import Testing

@testable import Kaji

@Suite("STT WebSocket transport")
struct STTWebSocketTransportTests {
    @Test("transport follows open receive send ping and close states")
    func stateMachine() async throws {
        let fakeTask = FakeSTTWebSocketTask()
        let policy = try STTWebSocketPolicy(
            maximumOutboundMessageBytes: 16,
            maximumInboundMessageBytes: 16,
            maximumPendingSends: 2,
            openTimeout: 1,
            sendTimeout: 1,
            drainTimeout: 1,
            closeTimeout: 1
        )
        let transport = URLSessionSTTWebSocketTransport(
            taskFactory: FakeSTTWebSocketTaskFactory(task: fakeTask),
            policy: policy
        )
        let events = await transport.events()
        var iterator = events.makeAsyncIterator()
        let request = URLRequest(url: try #require(URL(string: "wss://stream.stt.example/v1")))

        try await transport.connect(request: request)

        #expect(await iterator.next() == .stateChanged(.connecting))
        #expect(await iterator.next() == .stateChanged(.open))
        #expect(fakeTask.didResume)
        #expect(fakeTask.pingCount == 1)

        await fakeTask.push(.text("partial"))
        #expect(await iterator.next() == .message(.text("partial")))

        try await transport.send(.binary(Data([1, 2, 3])))
        #expect(fakeTask.sentMessages == [.binary(Data([1, 2, 3]))])

        try await transport.ping()
        #expect(await iterator.next() == .pong)
        #expect(fakeTask.pingCount == 2)

        try await transport.close(code: 1000, reason: "finished\nsecret")
        #expect(await transport.currentState() == .disconnected)
        #expect(fakeTask.cancelCode == 1000)
        #expect(fakeTask.cancelReason == Data("finishedsecret".utf8))
    }

    @Test("transport rejects oversized outbound messages without sending")
    func outboundLimit() async throws {
        let fakeTask = FakeSTTWebSocketTask()
        let policy = try STTWebSocketPolicy(
            maximumOutboundMessageBytes: 3,
            maximumInboundMessageBytes: 3,
            maximumPendingSends: 1,
            openTimeout: 1,
            sendTimeout: 1,
            drainTimeout: 1,
            closeTimeout: 1
        )
        let transport = URLSessionSTTWebSocketTransport(
            taskFactory: FakeSTTWebSocketTaskFactory(task: fakeTask),
            policy: policy
        )
        try await transport.connect(
            request: URLRequest(url: try #require(URL(string: "wss://stream.stt.example/v1")))
        )

        await #expect(throws: STTNetworkError.responseTooLarge) {
            try await transport.send(.text("four"))
        }
        #expect(fakeTask.sentMessages.isEmpty)
        await transport.cancel()
    }

    @Test("transport closes an oversized inbound frame with generic failure")
    func inboundLimit() async throws {
        let fakeTask = FakeSTTWebSocketTask()
        let policy = try STTWebSocketPolicy(
            maximumOutboundMessageBytes: 3,
            maximumInboundMessageBytes: 3,
            maximumPendingSends: 1,
            openTimeout: 1,
            sendTimeout: 1,
            drainTimeout: 1,
            closeTimeout: 1
        )
        let transport = URLSessionSTTWebSocketTransport(
            taskFactory: FakeSTTWebSocketTaskFactory(task: fakeTask),
            policy: policy
        )
        let events = await transport.events()
        var iterator = events.makeAsyncIterator()
        try await transport.connect(
            request: URLRequest(url: try #require(URL(string: "wss://stream.stt.example/v1")))
        )
        _ = await iterator.next()
        _ = await iterator.next()

        await fakeTask.push(.text("four"))

        #expect(await iterator.next() == .failed(.responseTooLarge))
        #expect(await iterator.next() == .closed(code: 1009))
        #expect(await iterator.next() == .stateChanged(.disconnected))
        #expect(fakeTask.cancelCode == 1009)
    }

    @Test("transport factory is injectable")
    func injectableFactory() async {
        let expected = FakeSTTWebSocketTransport()
        let factory = FakeSTTWebSocketTransportFactory(transport: expected)

        let created = factory.makeTransport()

        #expect(ObjectIdentifier(created as AnyObject) == ObjectIdentifier(expected))
    }

    @Test("opening times out and cancels an unresponsive handshake")
    func openTimeout() async throws {
        let fakeTask = FakeSTTWebSocketTask(pingDelay: .seconds(10))
        let policy = try STTWebSocketPolicy(
            maximumOutboundMessageBytes: 16,
            maximumInboundMessageBytes: 16,
            maximumPendingSends: 1,
            openTimeout: 0.1,
            sendTimeout: 1,
            drainTimeout: 1,
            closeTimeout: 1
        )
        let transport = URLSessionSTTWebSocketTransport(
            taskFactory: FakeSTTWebSocketTaskFactory(task: fakeTask),
            policy: policy
        )

        await #expect(throws: STTNetworkError.timedOut) {
            try await transport.connect(
                request: URLRequest(url: try #require(URL(string: "wss://stream.stt.example/v1")))
            )
        }
        #expect(await transport.currentState() == .disconnected)
        #expect(fakeTask.cancelCode == 1001)
    }

    @Test("URLSession WebSocket handshake redirects are denied")
    func redirectDenied() async throws {
        let delegate = STTWebSocketRedirectDenyingDelegate()
        let session = URLSession(configuration: .ephemeral)
        let startURL = try #require(URL(string: "https://stream.stt.example/start"))
        let redirectURL = try #require(URL(string: "https://other.example/next"))
        let task = session.dataTask(with: startURL)
        let response = try #require(HTTPURLResponse(
            url: startURL,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": "https://other.example/next"]
        ))
        let proposed = URLRequest(url: redirectURL)
        let result = RedirectResult()

        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: proposed
        ) { result.set($0) }

        #expect(result.value == nil)
        session.invalidateAndCancel()
    }

    @Test("URLSession task enforces the transport inbound frame limit")
    func nativeMaximumMessageSize() throws {
        let factory = URLSessionSTTWebSocketTaskFactory(
            configuration: .ephemeral,
            maximumMessageSize: 1234
        )

        let url = try #require(URL(string: "wss://stream.stt.example/v1"))
        let created = factory.makeTask(request: URLRequest(url: url))
        let task = try #require(created as? URLSessionSTTWebSocketTask)

        #expect(task.configuredMaximumMessageSize == 1234)
    }

    @Test("event buffering rejects an aggregate bound smaller than one inbound frame")
    func aggregateEventLimit() {
        #expect(throws: STTNetworkError.invalidConfiguration) {
            _ = try STTWebSocketPolicy(
                maximumInboundMessageBytes: 1024,
                maximumBufferedEventBytes: 512
            )
        }
    }

    @Test("startup control events reserve message capacity before a consumer attaches")
    func startupControlCapacity() async throws {
        let fakeTask = FakeSTTWebSocketTask()
        let policy = try STTWebSocketPolicy(
            maximumOutboundMessageBytes: 16,
            maximumInboundMessageBytes: 16,
            maximumPendingSends: 1,
            maximumBufferedEventCount: 1,
            maximumBufferedEventBytes: 16,
            openTimeout: 1,
            sendTimeout: 1,
            drainTimeout: 1,
            closeTimeout: 1
        )
        let transport = URLSessionSTTWebSocketTransport(
            taskFactory: FakeSTTWebSocketTaskFactory(task: fakeTask),
            policy: policy
        )
        try await transport.connect(
            request: URLRequest(url: try #require(URL(string: "wss://stream.stt.example/v1")))
        )
        await fakeTask.push(.text("payload"))
        try await Task.sleep(for: .milliseconds(20))
        var iterator = await transport.events().makeAsyncIterator()

        #expect(await iterator.next() == .stateChanged(.connecting))
        #expect(await iterator.next() == .stateChanged(.open))
        #expect(await iterator.next() == .message(.text("payload")))
        await transport.cancel()
    }

    @Test("message queue overflow closes with 1009 and a retryable network failure")
    func messageQueueOverflow() async throws {
        let fakeTask = FakeSTTWebSocketTask()
        let policy = try STTWebSocketPolicy(
            maximumOutboundMessageBytes: 16,
            maximumInboundMessageBytes: 16,
            maximumPendingSends: 1,
            maximumBufferedEventCount: 1,
            maximumBufferedEventBytes: 16,
            openTimeout: 1,
            sendTimeout: 1,
            drainTimeout: 1,
            closeTimeout: 1
        )
        let transport = URLSessionSTTWebSocketTransport(
            taskFactory: FakeSTTWebSocketTaskFactory(task: fakeTask),
            policy: policy
        )
        try await transport.connect(
            request: URLRequest(url: try #require(URL(string: "wss://stream.stt.example/v1")))
        )
        await fakeTask.push(.text("first"))
        await fakeTask.push(.text("second"))
        for _ in 0 ..< 100 where fakeTask.cancelCode != 1009 {
            try await Task.sleep(for: .milliseconds(5))
        }
        var iterator = await transport.events().makeAsyncIterator()

        #expect(await iterator.next() == .stateChanged(.connecting))
        #expect(await iterator.next() == .stateChanged(.open))
        #expect(await iterator.next() == .message(.text("first")))
        #expect(await iterator.next() == .failed(.connectionFailed))
        #expect(await iterator.next() == .closed(code: 1009))
        #expect(await iterator.next() == .stateChanged(.disconnected))
        #expect(fakeTask.cancelCode == 1009)
    }

    @Test("message queue aggregate byte overflow closes with 1009")
    func messageQueueByteOverflow() async throws {
        let fakeTask = FakeSTTWebSocketTask()
        let policy = try STTWebSocketPolicy(
            maximumOutboundMessageBytes: 4,
            maximumInboundMessageBytes: 4,
            maximumPendingSends: 1,
            maximumBufferedEventCount: 2,
            maximumBufferedEventBytes: 6,
            openTimeout: 1,
            sendTimeout: 1,
            drainTimeout: 1,
            closeTimeout: 1
        )
        let transport = URLSessionSTTWebSocketTransport(
            taskFactory: FakeSTTWebSocketTaskFactory(task: fakeTask),
            policy: policy
        )
        try await transport.connect(
            request: URLRequest(url: try #require(URL(string: "wss://stream.stt.example/v1")))
        )
        await fakeTask.push(.text("1234"))
        await fakeTask.push(.text("5678"))
        for _ in 0 ..< 100 where fakeTask.cancelCode != 1009 {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(fakeTask.cancelCode == 1009)
        #expect(await transport.currentState() == .disconnected)
    }
}

private final class RedirectResult: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    var value: URLRequest? {
        lock.withLock { request }
    }

    func set(_ request: URLRequest?) {
        lock.withLock { self.request = request }
    }
}

private final class FakeSTTWebSocketTask: STTWebSocketTasking, @unchecked Sendable {
    private let lock = NSLock()
    private let receiver = FakeSTTWebSocketReceiver()
    private var resumed = false
    private var pings = 0
    private var sent: [STTWebSocketMessage] = []
    private var retainedCloseCode: Int?
    private var retainedCloseReason: Data?
    private let pingDelay: Duration?

    init(pingDelay: Duration? = nil) {
        self.pingDelay = pingDelay
    }

    var closeCode: Int? {
        lock.withLock { retainedCloseCode }
    }

    var didResume: Bool {
        lock.withLock { resumed }
    }

    var pingCount: Int {
        lock.withLock { pings }
    }

    var sentMessages: [STTWebSocketMessage] {
        lock.withLock { sent }
    }

    var cancelCode: Int? {
        lock.withLock { retainedCloseCode }
    }

    var cancelReason: Data? {
        lock.withLock { retainedCloseReason }
    }

    func resume() {
        lock.withLock { resumed = true }
    }

    func send(_ message: STTWebSocketMessage) async {
        lock.withLock { sent.append(message) }
    }

    func receive() async throws -> STTWebSocketMessage {
        guard let message = await receiver.next() else {
            throw URLError(.networkConnectionLost)
        }
        return message
    }

    func ping() async throws {
        lock.withLock { pings += 1 }
        if let pingDelay { try await Task.sleep(for: pingDelay) }
    }

    func cancel(code: Int, reason: Data?) {
        lock.withLock {
            retainedCloseCode = code
            retainedCloseReason = reason
        }
        Task { await receiver.finish() }
    }

    func push(_ message: STTWebSocketMessage) async {
        await receiver.push(message)
    }
}

private actor FakeSTTWebSocketReceiver {
    private var messages: [STTWebSocketMessage] = []
    private var waiter: CheckedContinuation<STTWebSocketMessage?, Never>?
    private var finished = false

    func next() async -> STTWebSocketMessage? {
        if !messages.isEmpty { return messages.removeFirst() }
        if finished { return nil }
        return await withCheckedContinuation { waiter = $0 }
    }

    func push(_ message: STTWebSocketMessage) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: message)
        } else if !finished {
            messages.append(message)
        }
    }

    func finish() {
        finished = true
        waiter?.resume(returning: nil)
        waiter = nil
    }
}

private struct FakeSTTWebSocketTaskFactory: STTWebSocketTaskFactory {
    let task: FakeSTTWebSocketTask

    func makeTask(request _: URLRequest) -> any STTWebSocketTasking {
        task
    }
}

private final class FakeSTTWebSocketTransport: STTWebSocketTransporting, @unchecked Sendable {
    func events() async -> AsyncStream<STTWebSocketEvent> {
        AsyncStream { $0.finish() }
    }

    func currentState() async -> STTWebSocketState { .disconnected }
    func connect(request _: URLRequest) async throws {}
    func send(_: STTWebSocketMessage) async throws {}
    func ping() async throws {}
    func close(code _: Int, reason _: String?) async throws {}
    func cancel() async {}
}

private struct FakeSTTWebSocketTransportFactory: STTWebSocketTransportFactory {
    let transport: FakeSTTWebSocketTransport

    func makeTransport() -> any STTWebSocketTransporting {
        transport
    }
}
