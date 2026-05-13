import Foundation

@MainActor
@Observable
final class ToastState {
    static let shared = ToastState()

    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String) {
        self.message = message
        actionTitle = nil
        action = nil
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.clear()
        }
    }

    func showAction(message: String, actionTitle: String, timeout: UInt64 = 8_000_000_000, action: @escaping () -> Void) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled, let self else { return }
            self.clear()
        }
    }

    func dismissActionToast() {
        guard actionTitle != nil else { return }
        clear()
    }

    func performAction() {
        let action = action
        clear()
        action?()
    }

    func clear() {
        dismissTask?.cancel()
        message = nil
        actionTitle = nil
        action = nil
    }
}
