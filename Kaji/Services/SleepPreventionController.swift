import AppKit
import Foundation

@MainActor @Observable
final class SleepPreventionController {
    static let shared = SleepPreventionController()

    private let defaults: UserDefaults
    private let assertionManager: SystemSleepAssertionManaging
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var hasStopped = false

    private(set) var isEnabled: Bool
    private(set) var systemSleepAssertionStatus: SystemSleepAssertionStatus = .inactive

    var isAssertionActive: Bool {
        isEnabled && systemSleepAssertionStatus == .active
    }

    init(
        defaults: UserDefaults = .standard,
        assertionManager: SystemSleepAssertionManaging = IOKitSystemSleepAssertionManager(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.assertionManager = assertionManager
        self.notificationCenter = notificationCenter
        defaults.removeObject(forKey: "kaji.power.preventBatteryLidCloseSleep")
        isEnabled = SleepPreventionPreferences.isEnabled(defaults: defaults)
        observeLifecycleChanges()
        if isEnabled {
            reconcile()
        }
    }

    var title: String {
        SleepPreventionDisplayText.title(isEnabled: isEnabled)
    }

    var detail: String {
        SleepPreventionDisplayText.detail(
            isEnabled: isEnabled,
            systemSleepAssertionStatus: systemSleepAssertionStatus
        )
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else {
            reconcile()
            return
        }
        isEnabled = enabled
        SleepPreventionPreferences.setEnabled(enabled, defaults: defaults)
        systemSleepAssertionStatus = enabled ? assertionManager.begin() : assertionManager.end()
    }

    func reconcile() {
        systemSleepAssertionStatus = isEnabled ? assertionManager.reconcile() : assertionManager.end()
    }

    func verifyAssertionOwnership() -> Bool {
        guard isEnabled else { return false }
        systemSleepAssertionStatus = assertionManager.reconcile()
        return systemSleepAssertionStatus == .active
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        systemSleepAssertionStatus = assertionManager.end()
    }

    private func observeLifecycleChanges() {
        observers = [
            notificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.reconcile() }
            },
            notificationCenter.addObserver(
                forName: .NSProcessInfoPowerStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.reconcile() }
            },
        ]
    }
}
