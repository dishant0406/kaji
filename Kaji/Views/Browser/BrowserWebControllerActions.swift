import Foundation

extension BrowserWebController {
    func goBack() {
        guard browserView?.canGoBack == true else { return }
        browserView?.goBack()
    }

    func goForward() {
        guard browserView?.canGoForward == true else { return }
        browserView?.goForward()
    }

    func reload() {
        browserView?.reload()
    }

    func click(selector: String) async throws {
        try await click(KajiBrowserClickRequest(
            target: nil,
            selector: selector,
            button: "left",
            doubleClick: false,
            x: nil,
            y: nil
        ))
    }

    func fill(selector: String, text: String) async throws {
        try await fill(target: nil, selector: selector, text: text)
    }

    func typeText(_ text: String, selector: String) async throws {
        try await typeText(text, target: nil, selector: selector, slowly: false)
    }

    func click(_ request: KajiBrowserClickRequest) async throws {
        try await runActionScript(KajiBrowserInteractionScripts.click(request))
    }

    func hover(target: String?, selector: String?) async throws {
        try await runActionScript(KajiBrowserInteractionScripts.hover(target: target, selector: selector))
    }

    func drag(startTarget: String?, endTarget: String?) async throws {
        try await runActionScript(KajiBrowserInteractionScripts.drag(startTarget: startTarget, endTarget: endTarget))
    }

    func fill(target: String?, selector: String?, text: String) async throws {
        try await runActionScript(KajiBrowserFormScripts.fill(target: target, selector: selector, text: text, append: false))
    }

    func fillForm(fields: [[String: Any]]) async throws {
        try await runActionScript(KajiBrowserFormScripts.fillForm(fields: fields))
    }

    func typeText(_ text: String, target: String?, selector: String?, slowly _: Bool) async throws {
        try await runActionScript(KajiBrowserFormScripts.fill(target: target, selector: selector, text: text, append: true))
    }

    func selectOption(target: String?, selector: String?, values: [String]) async throws {
        try await runActionScript(KajiBrowserFormScripts.selectOption(target: target, selector: selector, values: values))
    }

    func pressKey(_ key: String) async throws {
        try await runActionScript(KajiBrowserInteractionScripts.pressKey(key))
    }

    func waitForSelector(_ selector: String, timeout: Duration = .seconds(10)) async throws -> Bool {
        try await waitForTarget(nil, selector: selector, timeout: timeout)
    }

    func waitForTarget(_ target: String?, selector: String?, timeout: Duration = .seconds(10)) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let result = try await evaluate(script: KajiBrowserWaitScripts.selector(target: target, selector: selector)) as? [String: Any]
            if result?["found"] as? Bool == true {
                return true
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        return false
    }

    func waitForText(_ text: String, gone: Bool, timeout: Duration = .seconds(10)) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let found = try await evaluate(script: KajiBrowserWaitScripts.text(text, gone: gone)) as? Bool
            if found == true {
                return true
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        return false
    }

    func readPage() async throws -> String {
        try await string(script: KajiBrowserPageScripts.readableText)
    }

    func snapshot() async throws -> Any {
        try await snapshot(depth: nil, boxes: true)
    }

    func snapshot(depth: Int?, boxes: Bool) async throws -> Any {
        try await evaluate(script: KajiBrowserSnapshotScripts.snapshot(depth: depth, boxes: boxes)) ?? [:]
    }

    func diagnosticsConsole(level: String?, all: Bool) async throws -> Any {
        try await evaluate(script: KajiBrowserDiagnosticScripts.console(level: level, all: all)) ?? []
    }

    func diagnosticsNetwork(filter: String?, includeStatic: Bool) async throws -> Any {
        try await evaluate(script: KajiBrowserDiagnosticScripts.network(filter: filter, includeStatic: includeStatic)) ?? [:]
    }

    func diagnosticsNetworkRequest(number: Int, part: String?) async throws -> Any {
        try await evaluate(script: KajiBrowserDiagnosticScripts.networkRequest(number: number, part: part)) ?? [:]
    }

    func uploadFiles(target: String?, selector: String?, files: [[String: String]]) async throws {
        try await runActionScript(KajiBrowserFormScripts.upload(target: target, selector: selector, files: files))
    }

    func drop(target: String?, selector: String?, data: [[String: String]], files: [[String: String]]) async throws {
        try await runActionScript(KajiBrowserFormScripts.drop(target: target, selector: selector, data: data, files: files))
    }

    func evaluate(script: String) async throws -> Any? {
        guard let browserView else { return nil }
        return try await KajiBrowserJavaScript.evaluate(script, in: browserView)
    }

    func string(script: String) async throws -> String {
        guard let browserView else { return "" }
        return try await KajiBrowserJavaScript.string(script, in: browserView)
    }

    func screenshotPNG(fullPage: Bool = false, target: String? = nil, selector: String? = nil) async throws -> Data? {
        guard let browserView else { return nil }
        return try await KajiBrowserScreenshot.pngData(from: browserView, fullPage: fullPage, target: target, selector: selector)
    }

    private func runActionScript(_ script: String) async throws {
        let result = try await evaluate(script: script) as? [String: Any]
        if result?["ok"] as? Bool == false {
            throw BrowserWebControllerActionError.failed(String(describing: result?["error"] ?? "failed"))
        }
    }
}

enum BrowserWebControllerActionError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            message
        }
    }
}
