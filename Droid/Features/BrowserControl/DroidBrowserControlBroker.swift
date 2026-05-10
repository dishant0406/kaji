import Foundation
import Network

final class DroidBrowserControlBroker: @unchecked Sendable {
    static let shared = DroidBrowserControlBroker()

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "DroidBrowserControlBroker")
    private var listener: NWListener?
    private var stateStorage: DroidBrowserBrokerState?

    private init() {}

    func ensureStarted(sessionID: String = "default") -> DroidBrowserBrokerState? {
        if let existing = lock.withLock({ stateStorage }) { return existing }
        guard let listener = try? NWListener(using: .tcp, on: .any) else { return nil }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                ready.signal()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 2) == .success else {
            listener.cancel()
            return nil
        }
        guard let port = listener.port, port.rawValue > 0 else {
            listener.cancel()
            return nil
        }
        let state = DroidBrowserBrokerState(
            port: port.rawValue,
            token: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            sessionID: sessionID,
            cdpPort: nil
        )
        lock.withLock {
            self.listener = listener
            self.stateStorage = state
        }
        return state
    }

    func updateRuntime(_ runtime: DroidBrowserRuntimeInfo) {
        lock.withLock {
            guard let stateStorage else { return }
            self.stateStorage = DroidBrowserBrokerState(
                port: stateStorage.port,
                token: stateStorage.token,
                sessionID: stateStorage.sessionID,
                cdpPort: runtime.remoteDebuggingPort
            )
        }
    }

    func state() -> DroidBrowserBrokerState? {
        lock.withLock { stateStorage }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            Task {
                let response = await self?.response(for: request) ?? Self.notFound()
                connection.send(content: response.data, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func response(for rawRequest: String) async -> DroidBrowserHTTPResponse {
        guard let request = DroidBrowserHTTPRequest(raw: rawRequest) else { return Self.badRequest() }
        switch (request.method, request.path) {
        case ("GET", "/status"):
            return DroidBrowserHTTPResponse(status: "200 OK", body: statusBody())
        case ("POST", "/browser"):
            guard isAuthorized(request) else { return Self.unauthorized() }
            return await browserResponse(for: request)
        default:
            return Self.notFound()
        }
    }

    private func browserResponse(for request: DroidBrowserHTTPRequest) async -> DroidBrowserHTTPResponse {
        guard let command = DroidBrowserControlCommand(
            body: request.body,
            defaultSessionID: state()?.sessionID ?? "default"
        )
        else { return Self.badRequest() }
        let body = await DroidBrowserControlRegistry.shared.handle(command)
        return DroidBrowserHTTPResponse(status: "200 OK", body: body)
    }

    private func isAuthorized(_ request: DroidBrowserHTTPRequest) -> Bool {
        guard let token = state()?.token else { return false }
        if request.headers["authorization"] == "Bearer \(token)" { return true }
        return request.headers["x-droid-browser-token"] == token
    }

    private func statusBody() -> String {
        let state = state()
        let values: [String: Any?] = [
            "connected": state?.cdpPort != nil,
            "brokerUrl": state?.brokerURL,
            "sessionId": state?.sessionID,
            "cdpUrl": state?.cdpURL,
            "cdpPort": state?.cdpPort,
        ]
        return DroidBrowserControlJSON.body(values.compactMapValues { $0 })
    }

    private static func badRequest() -> DroidBrowserHTTPResponse {
        DroidBrowserHTTPResponse(status: "400 Bad Request", body: "{\"error\":\"bad_request\"}")
    }

    private static func unauthorized() -> DroidBrowserHTTPResponse {
        DroidBrowserHTTPResponse(status: "401 Unauthorized", body: "{\"error\":\"unauthorized\"}")
    }

    private static func notFound() -> DroidBrowserHTTPResponse {
        DroidBrowserHTTPResponse(status: "404 Not Found", body: "{\"error\":\"not_found\"}")
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
