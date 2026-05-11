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
        guard let target = sessions[command.sessionID] else {
            return KajiBrowserControlJSON.body([
                "connected": false,
                "error": "browser_panel_not_open",
                "sessionId": command.sessionID,
            ])
        }
        let result = await run(command, target: target)
        return KajiBrowserControlJSON.body(result)
    }

    private func run(_ command: KajiBrowserControlCommand, target: KajiBrowserSessionTarget) async -> [String: Any] {
        switch command.action {
        case "current":
            return current(target: target)
        case "navigate":
            return navigate(command.arguments, target: target)
        case "new_tab":
            return newTab(command.arguments, target: target)
        case "back":
            target.selectedController?.goBack()
            return current(target: target)
        case "forward":
            target.selectedController?.goForward()
            return current(target: target)
        case "reload":
            target.selectedController?.reload()
            return current(target: target)
        case "read_page":
            return await readPage(target: target)
        case "screenshot":
            return screenshot(target: target)
        default:
            return ["connected": true, "error": "unknown_action", "action": command.action]
        }
    }

    private func navigate(_ arguments: [String: String], target: KajiBrowserSessionTarget) -> [String: Any] {
        guard let url = arguments["url"], !url.isEmpty else {
            return ["connected": true, "error": "missing_url"]
        }
        target.selectedController?.navigate(to: url)
        return current(target: target)
    }

    private func newTab(_ arguments: [String: String], target: KajiBrowserSessionTarget) -> [String: Any] {
        let page = target.state.openPage(url: arguments["url"] ?? BrowserPaneState.defaultURL)
        target.controllers.controller(for: page.id).ensureStarted(url: page.url)
        return current(target: target)
    }

    private func readPage(target: KajiBrowserSessionTarget) async -> [String: Any] {
        let text = await readableText(target: target)
        target.state.pageSummary = text
        var result = current(target: target)
        result["text"] = text
        result["readable"] = readablePayload(text: text, target: target)
        return result
    }

    private func readableText(target: KajiBrowserSessionTarget) async -> String {
        for _ in 0 ..< 10 {
            let text = await (try? target.selectedController?.readPage()) ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
                return text
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return await (try? target.selectedController?.readPage()) ?? ""
    }

    private func readablePayload(text: String, target: KajiBrowserSessionTarget) -> String {
        let page = target.state.selectedPage
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "Title: \(page?.title ?? "Browser")",
            "URL: \(page?.url ?? "")",
            "",
            trimmed.isEmpty ? "No page text was exposed by Chromium yet. Use kaji_browser_screenshot for visual inspection." : text,
        ].joined(separator: "\n")
    }

    private func screenshot(target: KajiBrowserSessionTarget) -> [String: Any] {
        guard let data = target.selectedController?.screenshotPNG(), !data.isEmpty else {
            return ["connected": false, "error": "screenshot_unavailable"]
        }
        var result = current(target: target)
        result["mimeType"] = "image/png"
        result["imageBase64"] = data.base64EncodedString()
        result["bytes"] = data.count
        return result
    }

    private func current(target: KajiBrowserSessionTarget) -> [String: Any] {
        let page = target.state.selectedPage
        let controller = page.map { target.controllers.controller(for: $0.id) }
        return [
            "connected": controller?.isReady == true,
            "selectedTabId": page?.id.uuidString ?? "",
            "url": page?.url ?? "",
            "title": page?.title ?? "Browser",
            "tabs": target.state.pages.map(pagePayload),
        ]
    }

    private func pagePayload(_ page: BrowserPageState) -> [String: Any] {
        ["id": page.id.uuidString, "url": page.url, "title": page.title]
    }
}

@MainActor
private struct KajiBrowserSessionTarget {
    let state: BrowserPaneState
    let controllers: BrowserControllerRegistry
    let close: () -> Void

    var selectedController: BrowserWebController? {
        state.selectedPage.map { controllers.controller(for: $0.id) }
    }
}
