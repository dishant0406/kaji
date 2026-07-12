import AppKit
import SwiftUI

@MainActor
@Observable
final class ModifierKeyMonitor {
    static let shared = ModifierKeyMonitor()

    private(set) var commandHeld = false
    private(set) var controlHeld = false
    private(set) var shiftHeld = false
    private(set) var optionHeld = false
    private(set) var showHints = false
    private(set) var activeModifiers: NSEvent.ModifierFlags = []
    private var monitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var hintTimer: Timer?

    private static let hintDelay: TimeInterval = 0.45
    private static let shiftOnlyHintDelay: TimeInterval = 0.75

    private init() {}

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            MainActor.assumeIsolated {
                self.updateFlags(flags)
            }
            return event
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                self.updateFlags(flags)
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        monitor = nil
        activationObserver = nil
        cancelHint()
        commandHeld = false
        controlHeld = false
        shiftHeld = false
        optionHeld = false
    }

    func isHolding(modifiers: UInt) -> Bool {
        guard showHints else { return false }
        let flags = NSEvent.ModifierFlags(rawValue: modifiers).intersection(KeyCombo.supportedModifierMask)
        let active = activeModifiers.intersection(KeyCombo.supportedModifierMask)
        guard !flags.isEmpty, !active.isEmpty else { return false }
        return !flags.isDisjoint(with: active)
    }

    func matchesHeldModifiers(_ combo: KeyCombo) -> Bool {
        guard showHints else { return false }
        let flags = combo.nsModifierFlags.intersection(KeyCombo.supportedModifierMask)
        guard !flags.isEmpty else { return false }
        return flags.isSubset(of: activeModifiers.intersection(KeyCombo.supportedModifierMask))
    }

    private func updateFlags(_ flags: NSEvent.ModifierFlags) {
        let previousModifiers = activeModifiers
        activeModifiers = flags.intersection(KeyCombo.supportedModifierMask)
        commandHeld = flags.contains(.command)
        controlHeld = flags.contains(.control)
        shiftHeld = flags.contains(.shift)
        optionHeld = flags.contains(.option)
        if activeModifiers.isEmpty {
            cancelHint()
        } else if activeModifiers != previousModifiers {
            scheduleHint()
        }
    }

    private func scheduleHint() {
        hintTimer?.invalidate()
        showHints = false
        let delay = activeModifiers == [.shift] ? Self.shiftOnlyHintDelay : Self.hintDelay
        hintTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.activeModifiers.isEmpty else { return }
                self.showHints = true
            }
        }
    }

    private func cancelHint() {
        hintTimer?.invalidate()
        hintTimer = nil
        activeModifiers = []
        showHints = false
    }
}
