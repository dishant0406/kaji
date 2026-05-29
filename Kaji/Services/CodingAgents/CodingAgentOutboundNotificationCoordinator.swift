import Foundation

@MainActor
final class CodingAgentOutboundNotificationCoordinator {
    static let shared = CodingAgentOutboundNotificationCoordinator()

    struct PendingKey: Hashable {
        let source: NotificationRouteSource
        let project: String
        let worktree: String
    }

    private let delay: Duration
    private let sleep: @Sendable (Duration) async -> Void
    private var pendingGenericTasks: [PendingKey: Task<Void, Never>] = [:]

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
        notification: KajiNotification,
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

        let key = pendingKey(for: event)
        pendingGenericTasks[key]?.cancel()
        pendingGenericTasks[key] = nil
        Task { await send(event) }
    }

    private func scheduleGeneric(
        event: NotificationOutboundEvent,
        send: @escaping @Sendable (NotificationOutboundEvent) async -> Void
    ) {
        let key = pendingKey(for: event)
        pendingGenericTasks[key]?.cancel()
        pendingGenericTasks[key] = Task { [delay, sleep] in
            await sleep(delay)
            guard !Task.isCancelled else { return }
            await send(event)
            await MainActor.run {
                self.pendingGenericTasks[key] = nil
            }
        }
    }

    private func shouldDelayGenericCompletion(_ notification: KajiNotification) -> Bool {
        AIProviderRegistry.shared.notificationPolicy(for: notification.source).coalesceGenericCompletions
    }

    private func isGeneric(_ body: String) -> Bool {
        let normalized = body.lowercased()
        return normalized == "turn completed" || normalized.hasPrefix("turn completed (")
    }

    private func pendingKey(for event: NotificationOutboundEvent) -> PendingKey {
        PendingKey(source: event.source, project: event.project, worktree: event.worktree)
    }
}
