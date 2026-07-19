import Foundation
@preconcurrency import ScreenCaptureKit
import Testing

@testable import Kaji

@MainActor
@Suite("Meeting content sharing picker")
struct MeetingContentSharingPickerTests {
    @Test("cancellation callback hops from replayd queue to main actor")
    func cancellationCallbackExecutorHop() async throws {
        let control = FakeMeetingContentSharingPickerControl()
        let picker = MeetingContentSharingPicker(picker: control)
        let selection = Task { try await picker.selectApplication() }
        let observer = try await waitForPresentation(control)

        invokeCancellation(fromBackgroundQueue: observer, repeatCount: 2)

        await #expect(throws: MeetingContentPickerError.cancelled) {
            try await selection.value
        }
        try await waitUntil { control.removeCount == 1 }
        try await Task.sleep(for: .milliseconds(25))
        #expect(!picker.isActive)
        #expect(!control.isActive)
        #expect(control.removeCount == 1)
    }

    @Test("failure callback hops from replayd queue to main actor")
    func failureCallbackExecutorHop() async throws {
        let control = FakeMeetingContentSharingPickerControl()
        let picker = MeetingContentSharingPicker(picker: control)
        let selection = Task { try await picker.selectApplication() }
        let observer = try await waitForPresentation(control)

        invokeFailure(fromBackgroundQueue: observer)

        await #expect(throws: MeetingContentPickerError.failed) {
            try await selection.value
        }
        #expect(!picker.isActive)
        #expect(!control.isActive)
        #expect(control.removeCount == 1)
    }

    @Test("stale callbacks cannot finish the current selection")
    func staleCallbackDoesNotFinishCurrentSelection() async throws {
        let control = FakeMeetingContentSharingPickerControl()
        let picker = MeetingContentSharingPicker(picker: control)
        let firstSelection = Task { try await picker.selectApplication() }
        let staleObserver = try await waitForPresentation(control)
        invokeCancellation(fromBackgroundQueue: staleObserver)
        await #expect(throws: MeetingContentPickerError.cancelled) {
            try await firstSelection.value
        }

        let currentSelection = Task { try await picker.selectApplication() }
        let currentObserver = try await waitForPresentation(control, count: 2)
        invokeFailure(fromBackgroundQueue: staleObserver)
        try await Task.sleep(for: .milliseconds(25))
        #expect(picker.isActive)
        #expect(control.removeCount == 1)

        invokeCancellation(fromBackgroundQueue: currentObserver)
        await #expect(throws: MeetingContentPickerError.cancelled) {
            try await currentSelection.value
        }
        #expect(control.removeCount == 2)
    }

    @Test("task cancellation and callbacks after stop are idempotent")
    func taskCancellationAndLateCallback() async throws {
        let control = FakeMeetingContentSharingPickerControl()
        let picker = MeetingContentSharingPicker(picker: control)
        let selection = Task { try await picker.selectApplication() }
        let observer = try await waitForPresentation(control)

        selection.cancel()
        await #expect(throws: MeetingContentPickerError.cancelled) {
            try await selection.value
        }
        invokeFailure(fromBackgroundQueue: observer)
        invokeCancellation(fromBackgroundQueue: observer)
        try await Task.sleep(for: .milliseconds(25))

        #expect(!picker.isActive)
        #expect(control.removeCount == 1)
    }

    @Test("callback after picker deallocation is safe")
    func callbackAfterDeinit() async throws {
        let (observer, pickerReference) = try await stoppedObserver()
        #expect(pickerReference.value == nil)

        invokeFailure(fromBackgroundQueue: observer)
        try await Task.sleep(for: .milliseconds(25))
    }

    private func stoppedObserver() async throws -> (UncheckedObserver, WeakPickerReference) {
        let control = FakeMeetingContentSharingPickerControl()
        let picker = MeetingContentSharingPicker(picker: control)
        let pickerReference = WeakPickerReference(picker)
        let selection = Task { try await picker.selectApplication() }
        let observer = try await waitForPresentation(control)
        picker.cancel()
        await #expect(throws: MeetingContentPickerError.cancelled) {
            try await selection.value
        }
        return (observer, pickerReference)
    }

    private func invokeCancellation(fromBackgroundQueue observer: UncheckedObserver, repeatCount: Int = 1) {
        DispatchQueue.global().async {
            for _ in 0 ..< repeatCount {
                observer.value.contentSharingPicker(SCContentSharingPicker.shared, didCancelFor: nil)
            }
        }
    }

    private func invokeFailure(fromBackgroundQueue observer: UncheckedObserver) {
        DispatchQueue.global().async {
            observer.value.contentSharingPickerStartDidFailWithError(NSError(domain: "test", code: 1))
        }
    }

    private func waitForPresentation(
        _ control: FakeMeetingContentSharingPickerControl,
        count: Int = 1
    ) async throws -> UncheckedObserver {
        try await waitUntil { control.presentCount == count }
        #expect(control.isActive)
        #expect(control.defaultConfiguration.allowedPickerModes == .singleApplication)
        #expect(!control.defaultConfiguration.allowsChangingSelectedContent)
        return try #require(control.currentObserver)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !condition(), clock.now < deadline {
            try await clock.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}

private struct UncheckedObserver: @unchecked Sendable {
    let value: any SCContentSharingPickerObserver
}

@MainActor
private final class WeakPickerReference {
    private(set) weak var value: MeetingContentSharingPicker?

    init(_ value: MeetingContentSharingPicker) {
        self.value = value
    }
}

@MainActor
private final class FakeMeetingContentSharingPickerControl: MeetingContentSharingPickerControlling {
    var defaultConfiguration = SCContentSharingPickerConfiguration()
    var isActive = false
    private(set) var addCount = 0
    private(set) var removeCount = 0
    private(set) var presentCount = 0
    private(set) var currentObserver: UncheckedObserver?

    func add(_ observer: any SCContentSharingPickerObserver) {
        addCount += 1
        currentObserver = UncheckedObserver(value: observer)
    }

    func remove(_: any SCContentSharingPickerObserver) {
        removeCount += 1
    }

    func present() {
        presentCount += 1
    }
}
