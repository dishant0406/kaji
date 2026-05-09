import Foundation
import Network

@MainActor
final class DroidBrowserAgentService {
    static let shared = DroidBrowserAgentService()

    private var listener: NWListener?
    private var port: UInt16?
    private var targets: [String: DroidBrowserAgentTarget] = [:]

    func environment(worktreePath: String, mcpCommand: String?) -> [(key: String, value: String)] {
        guard let mcpCommand, let endpoint = startEndpoint() else { return [] }
        return [
            (key: "DROID_BROWSER_ENDPOINT", value: endpoint),
            (key: "DROID_BROWSER_SESSION_ID", value: Self.sessionID(for: worktreePath)),
            (key: "DROID_BROWSER_MCP_COMMAND", value: mcpCommand),
        ]
    }

    func register(worktreePath: String, state: BrowserPaneState, controller: BrowserWebController?) {
        guard let controller else { return }
        targets[Self.sessionID(for: worktreePath)] = DroidBrowserAgentTarget(state: state, controller: controller)
        _ = startEndpoint()
    }

    func unregister(worktreePath: String) {
        targets.removeValue(forKey: Self.sessionID(for: worktreePath))
    }

    static func sessionID(for worktreePath: String) -> String {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in worktreePath.utf8 {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return String(value, radix: 16)
    }

    private func startEndpoint() -> String? {
        if let port { return "http://127.0.0.1:\(port)" }
        do {
            let listener = try NWListener(using: .tcp, on: .any)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.handle(connection) }
            }
            listener.stateUpdateHandler = { _ in }
            listener.start(queue: .main)
            self.listener = listener
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            guard let port = listener.port?.rawValue else { return nil }
            self.port = port
            return "http://127.0.0.1:\(port)"
        } catch {
            return nil
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            Task { @MainActor in
                await self?.respond(to: connection, data: data ?? Data())
            }
        }
    }

    private func respond(to connection: NWConnection, data: Data) async {
        let result = await response(for: data)
        connection.send(content: result, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func response(for data: Data) async -> Data {
        guard let request = String(data: data, encoding: .utf8) else {
            return http(status: 400, body: ["error": "Invalid request"])
        }
        guard request.hasPrefix("POST /browser ") else {
            return http(status: 404, body: ["error": "Not found"])
        }
        let body = request.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
        guard let payload = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] else {
            return http(status: 400, body: ["error": "Invalid JSON"])
        }
        let action = payload["action"] as? String ?? ""
        let sessionID = payload["sessionID"] as? String ?? ""
        guard let target = targets[sessionID], let controller = target.controller else {
            return http(status: 409, body: ["error": "Open the Droid browser panel for this worktree first"])
        }
        do {
            return try await http(status: 200, body: target.perform(action: action, payload: payload, controller: controller))
        } catch {
            return http(status: 500, body: ["error": error.localizedDescription])
        }
    }

    private func http(status: Int, body: [String: Any]) -> Data {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let head = [
            "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")",
            "Content-Type: application/json",
            "Content-Length: \(data.count)",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        return Data(head.utf8) + data
    }
}

@MainActor
private final class DroidBrowserAgentTarget {
    weak var state: BrowserPaneState?
    weak var controller: BrowserWebController?

    init(state: BrowserPaneState, controller: BrowserWebController) {
        self.state = state
        self.controller = controller
    }

    func perform(action: String, payload: [String: Any], controller: BrowserWebController) async throws -> [String: Any] {
        switch action {
        case "navigate":
            controller.navigate(to: payload["url"] as? String ?? "")
            return current()
        case "read_page":
            return try await current(extra: ["text": controller.readPage()])
        case "click":
            try await controller.click(selector: payload["selector"] as? String ?? "")
            return current()
        case "type":
            try await controller.typeText(payload["text"] as? String ?? "", selector: payload["selector"] as? String ?? "")
            return current()
        case "back":
            controller.goBack()
            return current()
        case "forward":
            controller.goForward()
            return current()
        case "reload":
            controller.reload()
            return current()
        case "current":
            return current()
        default:
            return ["error": "Unsupported action"]
        }
    }

    private func current(extra: [String: Any] = [:]) -> [String: Any] {
        var result: [String: Any] = [
            "url": state?.url ?? "",
            "title": state?.title ?? "Browser",
        ]
        extra.forEach { result[$0.key] = $0.value }
        return result
    }
}
