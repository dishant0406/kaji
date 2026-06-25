import Foundation

@MainActor
extension KajiBrowserControlRegistry {
    func readPage(target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let text = try await target.selectedController?.readPage() ?? ""
        target.state.pageSummary = text
        var result = current(target: target)
        result["text"] = text
        return result
    }

    func screenshot(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let data = try await target.selectedController?.screenshotPNG(
            fullPage: arguments.bool("fullPage") ?? false,
            target: arguments.string("target", "ref"),
            selector: arguments.string("selector")
        )
        guard let data, !data.isEmpty else {
            return ["connected": false, "error": "screenshot_unavailable"]
        }
        var result = current(target: target)
        result["mimeType"] = arguments.string("type") == "jpeg" ? "image/jpeg" : "image/png"
        result["imageBase64"] = data.base64EncodedString()
        result["bytes"] = data.count
        return result
    }

    func eval(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        guard let script = arguments.string("script", "function") else { return ["connected": true, "error": "missing_script"] }
        let value = try await target.selectedController?.evaluate(script: script)
        return current(target: target).merging(["value": KajiBrowserJavaScript.json(value)]) { _, new in new }
    }

    func snapshot(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let value = try await target.selectedController?.snapshot(
            depth: arguments.int("depth"),
            boxes: arguments.bool("boxes") ?? true
        )
        return current(target: target).merging(["snapshot": KajiBrowserJavaScript.json(value)]) { _, new in new }
    }

    func getText(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let script = KajiBrowserAutomationScripts.getText(selector: arguments.string("selector") ?? "body")
        let text = try await target.selectedController?.string(script: script) ?? ""
        return current(target: target).merging(["text": text]) { _, new in new }
    }

    func getHTML(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let script = KajiBrowserAutomationScripts.getHTML(selector: arguments.string("selector") ?? "html")
        let html = try await target.selectedController?.string(script: script) ?? ""
        return current(target: target).merging(["html": html]) { _, new in new }
    }

    func storageGet(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let script = KajiBrowserAutomationScripts.storageGet(type: arguments.string("type") ?? "local", key: arguments.string("key"))
        let value = try await target.selectedController?.evaluate(script: script)
        return current(target: target).merging(["value": KajiBrowserJavaScript.json(value)]) { _, new in new }
    }
}
