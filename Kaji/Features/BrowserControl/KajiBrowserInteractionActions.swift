import Foundation

@MainActor
extension KajiBrowserControlRegistry {
    func click(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let targetArgs = KajiBrowserTargetArguments(arguments)
        try await target.selectedController?.click(KajiBrowserClickRequest(
            target: targetArgs.target,
            selector: targetArgs.selector,
            button: arguments.string("button") ?? "left",
            doubleClick: arguments.bool("doubleClick") ?? false,
            x: arguments.double("x"),
            y: arguments.double("y")
        ))
        return current(target: target)
    }

    func hover(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let targetArgs = KajiBrowserTargetArguments(arguments)
        try await target.selectedController?.hover(target: targetArgs.target, selector: targetArgs.selector)
        return current(target: target)
    }

    func drag(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let start = arguments.string("startTarget", "startSelector")
        let end = arguments.string("endTarget", "endSelector")
        try await target.selectedController?.drag(startTarget: start, endTarget: end)
        return current(target: target)
    }

    func fill(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let targetArgs = KajiBrowserTargetArguments(arguments)
        try await target.selectedController?.fill(
            target: targetArgs.target,
            selector: targetArgs.selector,
            text: arguments.string("text", "value") ?? ""
        )
        return current(target: target)
    }

    func fillForm(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        try await target.selectedController?.fillForm(fields: arguments.objects("fields"))
        return current(target: target)
    }

    func type(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let targetArgs = KajiBrowserTargetArguments(arguments)
        try await target.selectedController?.typeText(
            arguments.string("text", "value") ?? "",
            target: targetArgs.target,
            selector: targetArgs.selector,
            slowly: arguments.bool("slowly") ?? false
        )
        if arguments.bool("submit") == true {
            try await target.selectedController?.pressKey("Enter")
        }
        return current(target: target)
    }

    func pressKey(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        guard let key = arguments.string("key") else { return ["connected": true, "error": "missing_key"] }
        try await target.selectedController?.pressKey(key)
        return current(target: target)
    }

    func selectOption(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let targetArgs = KajiBrowserTargetArguments(arguments)
        try await target.selectedController?.selectOption(
            target: targetArgs.target,
            selector: targetArgs.selector,
            values: arguments.strings("values")
        )
        return current(target: target)
    }

    func wait(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        if let time = arguments.double("time") {
            try await Task.sleep(for: .milliseconds(max(0, Int(time * 1000))))
            return current(target: target).merging(["found": true]) { _, new in new }
        }
        let timeout = Duration.milliseconds(arguments.int("timeoutMs") ?? 10000)
        let found = try await waitForPageCondition(arguments, target: target, timeout: timeout)
        return current(target: target).merging(["found": found]) { _, new in new }
    }

    private func waitForPageCondition(
        _ arguments: KajiBrowserControlArguments,
        target: KajiBrowserSessionTarget,
        timeout: Duration
    ) async throws -> Bool {
        if let textGone = arguments.string("textGone") {
            return try await target.selectedController?.waitForText(textGone, gone: true, timeout: timeout) ?? false
        }
        if let text = arguments.string("text") {
            return try await target.selectedController?.waitForText(text, gone: false, timeout: timeout) ?? false
        }
        let targetArgs = KajiBrowserTargetArguments(arguments)
        return try await target.selectedController?
            .waitForTarget(targetArgs.target, selector: targetArgs.selector, timeout: timeout) ?? false
    }
}
