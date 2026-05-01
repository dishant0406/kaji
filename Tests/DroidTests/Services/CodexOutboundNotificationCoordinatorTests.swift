import Foundation
import Testing

@testable import Droid

@MainActor
struct CodexOutboundNotificationCoordinatorTests {
    @Test
    func richerCodexMessageCancelsPendingGenericDelivery() async {
        let coordinator = CodexOutboundNotificationCoordinator(delay: .milliseconds(25))
        let recorder = DeliveryRecorder()

        coordinator.deliver(
            notification: notification(body: "Turn completed (codex-tui)"),
            event: event(body: "Turn completed (codex-tui)")
        ) { await recorder.record($0) }

        coordinator.deliver(
            notification: notification(body: "Hello."),
            event: event(body: "Hello.")
        ) { await recorder.record($0) }

        try? await Task.sleep(for: .milliseconds(120))

        #expect(await recorder.bodies() == ["Hello."])
    }

    @Test
    func genericCodexMessageDeliversWhenNoRicherUpdateArrives() async {
        let coordinator = CodexOutboundNotificationCoordinator(delay: .milliseconds(25))
        let recorder = DeliveryRecorder()

        coordinator.deliver(
            notification: notification(body: "Turn completed (codex-tui)"),
            event: event(body: "Turn completed (codex-tui)")
        ) { await recorder.record($0) }

        try? await Task.sleep(for: .milliseconds(120))

        #expect(await recorder.bodies() == ["Turn completed (codex-tui)"])
    }

    private func notification(body: String) -> DroidNotification {
        DroidNotification(
            paneID: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            areaID: UUID(),
            tabID: UUID(),
            worktreePath: "",
            source: .aiProvider("codex"),
            title: "Codex",
            body: body
        )
    }

    private func event(body: String) -> NotificationOutboundEvent {
        NotificationOutboundEvent(
            source: .codex,
            kind: .completed,
            title: "Codex",
            body: body,
            project: "Droid",
            worktree: "muxy",
            timestamp: Date()
        )
    }
}

private actor DeliveryRecorder {
    private var events: [NotificationOutboundEvent] = []

    func record(_ event: NotificationOutboundEvent) {
        events.append(event)
    }

    func bodies() -> [String] {
        events.map(\.body)
    }
}
