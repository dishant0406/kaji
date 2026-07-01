import Testing

@testable import Kaji

@Suite("Speech input footer visual state")
struct SpeechInputFooterVisualStateTests {
    @Test("idle maps to disabled when speech is off")
    func idleDisabled() {
        #expect(SpeechInputFooterVisualState.resolve(status: .idle, isEnabled: false) == .disabled)
    }

    @Test("idle maps to ready when speech is enabled")
    func idleReady() {
        #expect(SpeechInputFooterVisualState.resolve(status: .idle, isEnabled: true) == .ready)
    }

    @Test("active statuses keep distinct icon states")
    func activeStates() {
        #expect(SpeechInputFooterVisualState.resolve(status: .requestingPermission, isEnabled: true) == .requestingPermission)
        #expect(SpeechInputFooterVisualState.resolve(status: .listening, isEnabled: true) == .listening)
        #expect(SpeechInputFooterVisualState.resolve(status: .transcribing, isEnabled: true) == .transcribing)
    }

    @Test("progress statuses preserve progress")
    func progressStates() {
        let progress = SpeechDownloadProgress(fraction: 0.42, phaseTitle: "Downloading")
        #expect(SpeechInputFooterVisualState.resolve(status: .downloading(progress), isEnabled: true) == .downloading(progress))
        #expect(SpeechInputFooterVisualState.resolve(status: .preparing(progress), isEnabled: true) == .preparing(progress))
        #expect(SpeechInputFooterVisualState.resolve(status: .preparing(nil), isEnabled: true) == .preparing(nil))
    }

    @Test("error maps to failed and remains accessible")
    func failedState() {
        let state = SpeechInputFooterVisualState.resolve(status: .error("Microphone unavailable"), isEnabled: true)
        #expect(state == .failed("Microphone unavailable"))
        #expect(state.isFailed)
        #expect(state.accessibilityValue == "Microphone unavailable")
    }

    @Test("tooltips keep text out of the footer but available to users")
    func helpText() {
        #expect(SpeechInputFooterVisualState.ready.helpText(hotkey: "⌘⇧Space") == "Hold ⌘⇧Space for speech to text")
        #expect(SpeechInputFooterVisualState.disabled.helpText(hotkey: "⌘⇧Space") == "Speech to Text disabled")
        #expect(SpeechInputFooterVisualState.listening.helpText(hotkey: "⌘⇧Space") == "Listening")
    }
}
