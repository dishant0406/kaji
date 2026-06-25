import Foundation

@MainActor
extension KajiBrowserControlRegistry {
    func navigate(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        guard let url = arguments.string("url"), !url.isEmpty else { return ["connected": true, "error": "missing_url"] }
        guard let controller = target.selectedController else { return ["connected": false, "error": "page_not_ready"] }
        controller.navigate(to: url)
        let ready = try await controller.waitUntilReady(timeout: .milliseconds(arguments.int("timeoutMs") ?? 10000))
        return current(target: target).merging(["ready": ready]) { _, new in new }
    }

    func newTab(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) -> [String: Any] {
        let page = target.state.openPage(url: arguments.string("url") ?? BrowserPaneState.defaultURL)
        target.controllers.controller(for: page.id).ensureStarted(url: page.url)
        var result = current(target: target)
        result["pending"] = true
        return result
    }

    func back(target: KajiBrowserSessionTarget) -> [String: Any] {
        target.selectedController?.goBack()
        return current(target: target)
    }

    func forward(target: KajiBrowserSessionTarget) -> [String: Any] {
        target.selectedController?.goForward()
        return current(target: target)
    }

    func reload(target: KajiBrowserSessionTarget) -> [String: Any] {
        target.selectedController?.reload()
        return current(target: target)
    }

    func close(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) -> [String: Any] {
        let index = arguments.int("index")
        let page = index.flatMap { browserPage(at: $0, target: target) } ?? target.state.selectedPage
        guard let page else { return current(target: target) }
        if target.state.pages.count <= 1 {
            target.close()
            return ["connected": false, "closed": true]
        }
        target.state.closePage(id: page.id)
        return current(target: target)
    }

    func tabs(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) -> [String: Any] {
        switch arguments.string("action") ?? "list" {
        case "new": newTab(arguments, target: target)
        case "select": selectTab(arguments, target: target)
        case "close": close(arguments, target: target)
        default: current(target: target)
        }
    }

    func resize(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) -> [String: Any] {
        guard let width = arguments.int("width"), let height = arguments.int("height"), width > 0, height > 0 else {
            return ["connected": true, "error": "missing_size"]
        }
        target.selectedController?.resizeViewport(width: width, height: height)
        return current(target: target).merging(["width": width, "height": height]) { _, new in new }
    }

    private func selectTab(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) -> [String: Any] {
        if let id = arguments.string("id"), let uuid = UUID(uuidString: id) {
            target.state.selectPage(id: uuid)
            return current(target: target)
        }
        guard let index = arguments.int("index"), let page = browserPage(at: index, target: target) else {
            return ["connected": true, "error": "missing_tab"]
        }
        target.state.selectPage(id: page.id)
        target.controllers.controller(for: page.id).ensureStarted(url: page.url)
        return current(target: target)
    }

    private func browserPage(at index: Int, target: KajiBrowserSessionTarget) -> BrowserPageState? {
        guard target.state.pages.indices.contains(index) else { return nil }
        return target.state.pages[index]
    }
}
