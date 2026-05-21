import Foundation
import Network

final class KajiBrowserControlBroker: @unchecked Sendable {
    static let shared = KajiBrowserControlBroker()

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "KajiBrowserControlBroker")
    private var listener: NWListener?
    private var stateStorage: KajiBrowserBrokerState?

    private init() {}

    func ensureStarted(sessionID: String = "default") -> KajiBrowserBrokerState? {
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
        let state = KajiBrowserBrokerState(
            port: port.rawValue,
            token: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            sessionID: sessionID,
            cdpPort: nil
        )
        lock.withLock {
            self.listener = listener
            self.stateStorage = state
        }
        KajiBrowserSessionEnvironmentStore.write(state)
        return state
    }

    func updateRuntime(_ runtime: KajiBrowserRuntimeInfo) {
        updateState { stateStorage in
            KajiBrowserBrokerState(
                port: stateStorage.port,
                token: stateStorage.token,
                sessionID: stateStorage.sessionID,
                cdpPort: runtime.remoteDebuggingPort
            )
        }
    }

    func updateSession(_ sessionID: String) {
        updateState { stateStorage in
            KajiBrowserBrokerState(
                port: stateStorage.port,
                token: stateStorage.token,
                sessionID: sessionID,
                cdpPort: stateStorage.cdpPort
            )
        }
    }

    private func updateState(_ transform: (KajiBrowserBrokerState) -> KajiBrowserBrokerState) {
        let updated = lock.withLock { () -> KajiBrowserBrokerState? in
            guard let stateStorage else { return nil }
            let state = transform(stateStorage)
            self.stateStorage = state
            return state
        }
        if let updated {
            KajiBrowserSessionEnvironmentStore.write(updated)
        }
    }

    func state() -> KajiBrowserBrokerState? {
        lock.withLock { stateStorage }
    }

    func stop() {
        let listener = lock.withLock { () -> NWListener? in
            let listener = self.listener
            self.listener = nil
            self.stateStorage = nil
            return listener
        }
        listener?.cancel()
        KajiBrowserSessionEnvironmentStore.remove()
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

    private func response(for rawRequest: String) async -> KajiBrowserHTTPResponse {
        guard let request = KajiBrowserHTTPRequest(raw: rawRequest) else { return Self.badRequest() }
        switch (request.method, request.path) {
        case ("GET", "/status"):
            return KajiBrowserHTTPResponse(status: "200 OK", body: statusBody())
        case ("POST", "/browser"):
            guard isAuthorized(request) else { return Self.unauthorized() }
            return await browserResponse(for: request)
        default:
            return Self.notFound()
        }
    }

    private func browserResponse(for request: KajiBrowserHTTPRequest) async -> KajiBrowserHTTPResponse {
        guard let command = KajiBrowserControlCommand(
            body: request.body,
            defaultSessionID: state()?.sessionID ?? "default"
        )
        else { return Self.badRequest() }
        let body = await KajiBrowserControlRegistry.shared.handle(command)
        return KajiBrowserHTTPResponse(status: "200 OK", body: body)
    }

    private func isAuthorized(_ request: KajiBrowserHTTPRequest) -> Bool {
        guard let token = state()?.token else { return false }
        if request.headers["authorization"] == "Bearer \(token)" { return true }
        return request.headers["x-kaji-browser-token"] == token
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
        return KajiBrowserControlJSON.body(values.compactMapValues { $0 })
    }

    private static func badRequest() -> KajiBrowserHTTPResponse {
        KajiBrowserHTTPResponse(status: "400 Bad Request", body: "{\"error\":\"bad_request\"}")
    }

    private static func unauthorized() -> KajiBrowserHTTPResponse {
        KajiBrowserHTTPResponse(status: "401 Unauthorized", body: "{\"error\":\"unauthorized\"}")
    }

    private static func notFound() -> KajiBrowserHTTPResponse {
        KajiBrowserHTTPResponse(status: "404 Not Found", body: "{\"error\":\"not_found\"}")
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
