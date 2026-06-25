import Foundation

@MainActor
extension KajiBrowserControlRegistry {
    func consoleMessages(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let value = try await target.selectedController?.diagnosticsConsole(
            level: arguments.string("level"),
            all: arguments.bool("all") ?? false
        )
        return current(target: target).merging(["messages": KajiBrowserJavaScript.json(value)]) { _, new in new }
    }

    func networkRequests(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let value = try await target.selectedController?.diagnosticsNetwork(
            filter: arguments.string("filter"),
            includeStatic: arguments.bool("static") ?? false
        )
        return current(target: target).merging(["network": KajiBrowserJavaScript.json(value)]) { _, new in new }
    }

    func networkRequest(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        guard let number = arguments.int("number") else { return ["connected": true, "error": "missing_request_number"] }
        let value = try await target.selectedController?.diagnosticsNetworkRequest(number: number, part: arguments.string("part"))
        return current(target: target).merging(["request": KajiBrowserJavaScript.json(value)]) { _, new in new }
    }

    func handleDialog(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) -> [String: Any] {
        let accepted = target.selectedController?.handleDialog(
            accept: arguments.bool("accept") ?? true,
            promptText: arguments.string("promptText")
        ) ?? false
        return current(target: target).merging(["handled": accepted]) { _, new in new }
    }
}
