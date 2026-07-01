import AppKit
import Foundation

@MainActor
final class SpeechHotkeyMonitor {
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var flagsMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var isPressed = false
    private var onRelease: ((SpeechCaptureStopReason) -> Void)?

    func start(onPress: @escaping () -> Void, onRelease: @escaping (SpeechCaptureStopReason) -> Void) {
        stop()
        self.onRelease = onRelease
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.shouldCapturePress(event) else { return event }
            self.isPressed = true
            onPress()
            return nil
        }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyUp(event, consume: true)
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            self.handleFlagsChanged(event)
            return event
        }
        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor [weak self] in
                _ = self?.handleKeyUp(event, consume: false)
            }
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(event)
            }
        }
    }

    func stop() {
        remove(keyDownMonitor)
        remove(keyUpMonitor)
        remove(flagsMonitor)
        remove(globalKeyUpMonitor)
        remove(globalFlagsMonitor)
        keyDownMonitor = nil
        keyUpMonitor = nil
        flagsMonitor = nil
        globalKeyUpMonitor = nil
        globalFlagsMonitor = nil
        onRelease = nil
        isPressed = false
    }

    func forceRelease(_ reason: SpeechCaptureStopReason) {
        guard isPressed else { return }
        release(reason)
    }

    private func handleKeyUp(_ event: NSEvent, consume: Bool) -> NSEvent? {
        guard shouldCaptureRelease(event) else { return event }
        release(.shortcutReleased)
        return consume ? nil : event
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard isPressed else { return }
        let combo = SpeechInputSettingsStore.shared.settings.holdHotkey
        guard !combo.requiredModifiersArePressed(in: event.modifierFlags) else { return }
        release(.shortcutLost)
    }

    private func release(_ reason: SpeechCaptureStopReason) {
        isPressed = false
        onRelease?(reason)
    }

    private func remove(_ monitor: Any?) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func shouldCapturePress(_ event: NSEvent) -> Bool {
        guard SpeechInputSettingsStore.shared.settings.isEnabled else { return false }
        guard ShortcutContext.isMainWindow(NSApp.keyWindow) else { return false }
        let matcher = SpeechHotkeyMatcher(combo: SpeechInputSettingsStore.shared.settings.holdHotkey)
        return matcher.matchesPress(event)
    }

    private func shouldCaptureRelease(_ event: NSEvent) -> Bool {
        guard isPressed else { return false }
        let matcher = SpeechHotkeyMatcher(combo: SpeechInputSettingsStore.shared.settings.holdHotkey)
        return matcher.matchesRelease(event)
    }
}
