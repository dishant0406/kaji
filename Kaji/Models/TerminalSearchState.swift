import Foundation

@MainActor
@Observable
final class TerminalSearchState {
    typealias Delay = (Duration) async -> Void

    var needle: String = ""
    var total: Int?
    var selected: Int?
    var isVisible: Bool = false
    var focusVersion: Int = 0

    var displayText: String {
        guard let total else { return "" }
        guard let selected else { return "\(total) matches" }
        return "\(selected) of \(total)"
    }

    private let delay: Delay
    private var publishTask: Task<Void, Never>?
    private var lastPushedNeedle: String?
    private var sendNeedle: ((String) -> Void)?

    init(delay: @escaping Delay = TerminalSearchState.sleep) {
        self.delay = delay
    }

    func startPublishing(send: @escaping (String) -> Void) {
        publishTask?.cancel()
        publishTask = nil
        lastPushedNeedle = nil
        sendNeedle = send
    }

    func pushNeedle() {
        let nextNeedle = needle
        guard nextNeedle != lastPushedNeedle else { return }

        lastPushedNeedle = nextNeedle
        publishTask?.cancel()

        guard !nextNeedle.isEmpty else {
            sendNeedle?(nextNeedle)
            return
        }

        let delay = publishDelay(for: nextNeedle)
        publishTask = Task { [delay, nextNeedle] in
            await self.delay(delay)
            guard !Task.isCancelled else { return }
            self.sendNeedle?(nextNeedle)
        }
    }

    func stopPublishing() {
        publishTask?.cancel()
        publishTask = nil
        sendNeedle = nil
        lastPushedNeedle = nil
    }

    private func publishDelay(for needle: String) -> Duration {
        needle.count >= 3 ? .milliseconds(120) : .milliseconds(300)
    }

    private static func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}
