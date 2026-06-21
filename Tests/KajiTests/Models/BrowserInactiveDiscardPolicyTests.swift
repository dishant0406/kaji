import Foundation
import Testing

@testable import Kaji

@Suite("BrowserInactiveDiscardPolicy")
struct BrowserInactiveDiscardPolicyTests {
    @Test("schedules discard only for hidden retained panes")
    func schedulesDiscardOnlyForHiddenRetainedPanes() {
        #expect(BrowserInactiveDiscardPolicy.shouldScheduleDiscard(closeOnDisappear: false, paneIsVisible: false))
        #expect(!BrowserInactiveDiscardPolicy.shouldScheduleDiscard(closeOnDisappear: true, paneIsVisible: false))
        #expect(!BrowserInactiveDiscardPolicy.shouldScheduleDiscard(closeOnDisappear: false, paneIsVisible: true))
    }
}

@MainActor
@Suite("BrowserControllerRegistry discard")
struct BrowserControllerRegistryDiscardTests {
    @Test("scheduled discard closes retained controllers")
    func scheduledDiscardClosesControllers() async throws {
        let registry = BrowserControllerRegistry()
        let id = UUID()
        _ = registry.controller(for: id)

        registry.scheduleDiscard(after: .milliseconds(5))
        try await waitUntil {
            registry.controllerIDs.isEmpty
        }

        #expect(registry.controllerIDs.isEmpty)
    }

    @Test("cancelled discard keeps retained controllers")
    func cancelledDiscardKeepsControllers() async throws {
        let registry = BrowserControllerRegistry()
        let id = UUID()
        _ = registry.controller(for: id)

        registry.scheduleDiscard(after: .milliseconds(20))
        registry.cancelScheduledDiscard()
        try await Task.sleep(for: .milliseconds(40))

        #expect(registry.controllerIDs == [id])
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0 ..< 200 {
            if predicate() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
