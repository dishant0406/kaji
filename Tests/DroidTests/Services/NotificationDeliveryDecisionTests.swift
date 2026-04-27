import Testing

@testable import Droid

struct NotificationDeliveryDecisionTests {
    @Test
    func activeAppAndActiveTabPersistAsReadAndDeliver() {
        let decision = NotificationDeliveryDecision.resolve(
            isAppActive: true,
            isTargetTabActive: true
        )

        #expect(decision == .persistReadAndDeliver)
    }

    @Test
    func inactiveTabPersistsUnreadAndDelivers() {
        let decision = NotificationDeliveryDecision.resolve(
            isAppActive: true,
            isTargetTabActive: false
        )

        #expect(decision == .persistUnreadAndDeliver)
    }

    @Test
    func inactiveAppPersistsUnreadAndDelivers() {
        let decision = NotificationDeliveryDecision.resolve(
            isAppActive: false,
            isTargetTabActive: true
        )

        #expect(decision == .persistUnreadAndDeliver)
    }
}
