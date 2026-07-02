import Testing

@testable import Kaji

struct TerminalInjectedCommandDeliveryTests {
    @Test
    func repeatedSameCommandOnlyPreparesOneDelivery() {
        var delivery = TerminalInjectedCommandDelivery()

        let firstSet = delivery.setCommand(" codex ")
        let secondSet = delivery.setCommand("codex")
        let thirdSet = delivery.setCommand("codex\n")
        let firstPrepared = delivery.prepareDelivery()
        let secondPrepared = delivery.prepareDelivery()
        let fourthSet = delivery.setCommand("codex")
        let thirdPrepared = delivery.prepareDelivery()

        #expect(firstSet)
        #expect(!secondSet)
        #expect(!thirdSet)
        #expect(firstPrepared == "codex")
        #expect(secondPrepared == nil)
        #expect(!fourthSet)
        #expect(thirdPrepared == nil)
    }

    @Test
    func completedCommandCannotBePreparedAgainFromSwiftUIUpdates() {
        var delivery = TerminalInjectedCommandDelivery()

        let firstSet = delivery.setCommand("codex")
        let prepared = delivery.prepareDelivery()
        let completed = delivery.completePendingDelivery("codex")
        let secondSet = delivery.setCommand("codex")
        let secondPrepared = delivery.prepareDelivery()

        #expect(firstSet)
        #expect(prepared == "codex")
        #expect(completed)
        #expect(!secondSet)
        #expect(secondPrepared == nil)
    }

    @Test
    func changingCommandInvalidatesOlderPendingDelivery() {
        var delivery = TerminalInjectedCommandDelivery()

        let firstSet = delivery.setCommand("codex")
        let firstPrepared = delivery.prepareDelivery()
        let secondSet = delivery.setCommand("claude")
        let secondPrepared = delivery.prepareDelivery()
        let oldCompleted = delivery.completePendingDelivery("codex")
        let newCompleted = delivery.completePendingDelivery("claude")

        #expect(firstSet)
        #expect(firstPrepared == "codex")
        #expect(secondSet)
        #expect(secondPrepared == "claude")
        #expect(!oldCompleted)
        #expect(newCompleted)
    }

    @Test
    func clearingCommandInvalidatesPendingDelivery() {
        var delivery = TerminalInjectedCommandDelivery()

        let firstSet = delivery.setCommand("codex")
        let firstPrepared = delivery.prepareDelivery()
        let cleared = delivery.setCommand(" ")
        let clearedPrepared = delivery.prepareDelivery()
        let oldCompleted = delivery.completePendingDelivery("codex")
        let reset = delivery.setCommand("codex")
        let resetPrepared = delivery.prepareDelivery()

        #expect(firstSet)
        #expect(firstPrepared == "codex")
        #expect(cleared)
        #expect(clearedPrepared == nil)
        #expect(!oldCompleted)
        #expect(reset)
        #expect(resetPrepared == "codex")
    }

    @Test
    func canceledPendingDeliveryCanBePreparedAgain() {
        var delivery = TerminalInjectedCommandDelivery()

        let firstSet = delivery.setCommand("codex")
        let firstPrepared = delivery.prepareDelivery()
        delivery.cancelPendingDelivery("codex")
        let secondPrepared = delivery.prepareDelivery()

        #expect(firstSet)
        #expect(firstPrepared == "codex")
        #expect(secondPrepared == "codex")
    }
}
