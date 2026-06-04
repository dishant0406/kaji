import Foundation
import Testing

@testable import Kaji

@MainActor
struct CodingAgentOutboundNotificationCoordinatorTests {
    @Test
    func richerCodexMessageCancelsPendingGenericDelivery() async {
        let coordinator = CodingAgentOutboundNotificationCoordinator(
            delay: .seconds(1),
            sleep: { _ in
                while !Task.isCancelled {
                    await Task.yield()
                }
            },
            notificationPolicy: { _ in .init(coalesceGenericCompletions: true) }
        )
        let recorder = DeliveryRecorder()

        coordinator.deliver(
            notification: notification(body: "Turn completed (codex-tui)"),
            event: event(body: "Turn completed (codex-tui)")
        ) { await recorder.record($0) }

        coordinator.deliver(
            notification: notification(body: "Hello."),
            event: event(body: "Hello.")
        ) { await recorder.record($0) }

        _ = await recorder.waitForBodies(count: 1)
        await Task.yield()

        #expect(await recorder.bodies() == ["Hello."])
    }

    @Test
    func genericCodexMessageDeliversWhenNoRicherUpdateArrives() async {
        let coordinator = CodingAgentOutboundNotificationCoordinator(
            delay: .milliseconds(25),
            sleep: { _ in },
            notificationPolicy: { _ in .init(coalesceGenericCompletions: true) }
        )
        let recorder = DeliveryRecorder()

        coordinator.deliver(
            notification: notification(body: "Turn completed (codex-tui)"),
            event: event(body: "Turn completed (codex-tui)")
        ) { await recorder.record($0) }

        #expect(await recorder.waitForBodies(count: 1, timeout: .seconds(3)) == ["Turn completed (codex-tui)"])
    }

    private func notification(body: String) -> KajiNotification {
        KajiNotification(
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
            project: "Kaji",
            worktree: "muxy",
            timestamp: Date()
        )
    }
}

private actor DeliveryRecorder {
    private var events: [NotificationOutboundEvent] = []
    private let clock = ContinuousClock()

    func record(_ event: NotificationOutboundEvent) {
        events.append(event)
    }

    func bodies() -> [String] {
        events.map(\.body)
    }

    func waitForBodies(count: Int, timeout: Duration = .seconds(1)) async -> [String] {
        let deadline = clock.now.advanced(by: timeout)
        while events.count < count, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return bodies()
    }
}
