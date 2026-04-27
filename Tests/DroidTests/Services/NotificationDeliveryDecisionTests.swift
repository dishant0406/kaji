import Testing

@testable import Droid

struct NotificationDeliveryDecisionTests {
    @Test
    func activeAppAndActiveTabDeliverWithoutPersistence() {
        let decision = NotificationDeliveryDecision.resolve(
            isAppActive: true,
            isTargetTabActive: true
        )

        #expect(decision == .deliverOnly)
    }

    @Test
    func inactiveTabPersistsAndDelivers() {
        let decision = NotificationDeliveryDecision.resolve(
            isAppActive: true,
            isTargetTabActive: false
        )

        #expect(decision == .persistAndDeliver)
    }

    @Test
    func inactiveAppPersistsAndDelivers() {
        let decision = NotificationDeliveryDecision.resolve(
            isAppActive: false,
            isTargetTabActive: true
        )

        #expect(decision == .persistAndDeliver)
    }
}
