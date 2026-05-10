import Foundation

@MainActor
final class CodingAgentOutboundNotificationCoordinator {
    static let shared = CodingAgentOutboundNotificationCoordinator()

    private let delay: Duration
    private let sleep: @Sendable (Duration) async -> Void
    private var pendingGenericTask: Task<Void, Never>?

    init(
        delay: Duration = .seconds(2),
        sleep: @escaping @Sendable (Duration) async -> Void = {
            try? await Task.sleep(for: $0)
        }
    ) {
        self.delay = delay
        self.sleep = sleep
    }

    func deliver(
        notification: DroidNotification,
        event: NotificationOutboundEvent,
        send: @escaping @Sendable (NotificationOutboundEvent) async -> Void
    ) {
        guard shouldDelayGenericCompletion(notification) else {
            Task { await send(event) }
            return
        }

        if isGeneric(notification.body) {
            scheduleGeneric(event: event, send: send)
            return
        }

        pendingGenericTask?.cancel()
        pendingGenericTask = nil
        Task { await send(event) }
    }

    private func scheduleGeneric(
        event: NotificationOutboundEvent,
        send: @escaping @Sendable (NotificationOutboundEvent) async -> Void
    ) {
        pendingGenericTask?.cancel()
        pendingGenericTask = Task { [delay, sleep] in
            await sleep(delay)
            guard !Task.isCancelled else { return }
            await send(event)
            await MainActor.run {
                self.pendingGenericTask = nil
            }
        }
    }

    private func shouldDelayGenericCompletion(_ notification: DroidNotification) -> Bool {
        AIProviderRegistry.shared.notificationPolicy(for: notification.source).coalesceGenericCompletions
    }

    private func isGeneric(_ body: String) -> Bool {
        let normalized = body.lowercased()
        return normalized == "turn completed" || normalized.hasPrefix("turn completed (")
    }
}
