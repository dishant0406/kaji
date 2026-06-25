import Foundation

@MainActor
final class KajiBrowserControlRegistry {
    static let shared = KajiBrowserControlRegistry()
    private var sessions: [String: KajiBrowserSessionTarget] = [:]
    private init() {}

    func register(sessionID: String, state: BrowserPaneState, controllers: BrowserControllerRegistry, close: @escaping () -> Void) {
        sessions[sessionID] = KajiBrowserSessionTarget(state: state, controllers: controllers, close: close)
    }

    func unregister(sessionID: String) {
        sessions.removeValue(forKey: sessionID)
    }

    func handle(_ command: KajiBrowserControlCommand) async -> String {
        if command.action == "open_panel" { return panelResult(command, notification: .openBrowserPanel) }
        if command.action == "close_panel" { return panelResult(command, notification: .closeBrowserPanel) }
        guard let target = sessions[command.sessionID] else {
            return KajiBrowserControlJSON.body(["connected": false, "error": "browser_panel_not_open", "sessionId": command.sessionID])
        }
        return await KajiBrowserControlJSON.body(run(command, target: target))
    }

    private func panelResult(_ command: KajiBrowserControlCommand, notification: Notification.Name) -> String {
        NotificationCenter.default.post(name: notification, object: nil)
        return KajiBrowserControlJSON.body(["connected": false, "pending": true, "action": command.action, "sessionId": command.sessionID])
    }

    private func run(_ command: KajiBrowserControlCommand, target: KajiBrowserSessionTarget) async -> [String: Any] {
        do {
            switch command.action {
            case "current": return current(target: target)
            case "navigate": return try await navigate(command.arguments, target: target)
            case "new_tab": return newTab(command.arguments, target: target)
            case "back": return back(target: target)
            case "forward": return forward(target: target)
            case "reload": return reload(target: target)
            case "close": return close(command.arguments, target: target)
            case "tabs": return tabs(command.arguments, target: target)
            case "resize": return resize(command.arguments, target: target)
            case "read_page": return try await readPage(target: target)
            case "screenshot": return try await screenshot(command.arguments, target: target)
            case "eval": return try await eval(command.arguments, target: target)
            case "snapshot": return try await snapshot(command.arguments, target: target)
            case "click": return try await click(command.arguments, target: target)
            case "hover": return try await hover(command.arguments, target: target)
            case "drag": return try await drag(command.arguments, target: target)
            case "fill": return try await fill(command.arguments, target: target)
            case "fill_form": return try await fillForm(command.arguments, target: target)
            case "type": return try await type(command.arguments, target: target)
            case "press_key": return try await pressKey(command.arguments, target: target)
            case "select_option": return try await selectOption(command.arguments, target: target)
            case "wait": return try await wait(command.arguments, target: target)
            case "get_text": return try await getText(command.arguments, target: target)
            case "get_html": return try await getHTML(command.arguments, target: target)
            case "storage_get": return try await storageGet(command.arguments, target: target)
            case "console_messages": return try await consoleMessages(command.arguments, target: target)
            case "network_requests": return try await networkRequests(command.arguments, target: target)
            case "network_request": return try await networkRequest(command.arguments, target: target)
            case "handle_dialog": return handleDialog(command.arguments, target: target)
            case "file_upload": return try await fileUpload(command.arguments, target: target)
            case "drop": return try await drop(command.arguments, target: target)
            default: return ["connected": true, "error": "unknown_action", "action": command.action]
            }
        } catch {
            return ["connected": true, "error": error.localizedDescription, "action": command.action]
        }
    }

    func current(target: KajiBrowserSessionTarget) -> [String: Any] {
        let page = target.state.selectedPage
        let controller = page.map { target.controllers.controller(for: $0.id) }
        return [
            "connected": controller?.isReady == true,
            "engine": "webkit",
            "selectedTabId": page?.id.uuidString ?? "",
            "url": page?.url ?? "",
            "title": page?.title ?? "Browser",
            "dialogs": controller?.pendingDialogPayloads() ?? [],
            "tabs": target.state.pages.map(pagePayload),
        ]
    }

    private func pagePayload(_ page: BrowserPageState) -> [String: Any] {
        ["id": page.id.uuidString, "url": page.url, "title": page.title]
    }
}

@MainActor
struct KajiBrowserSessionTarget {
    let state: BrowserPaneState
    let controllers: BrowserControllerRegistry
    let close: () -> Void
    var selectedController: BrowserWebController? { state.selectedPage.map { controllers.controller(for: $0.id) } }
}
