import AppKit
import Testing

@testable import Kaji

@Suite("Speech input policy")
struct SpeechInputPolicyTests {
    @Test("settings falls back to default model")
    func catalogFallback() {
        let settings = SpeechInputSettings(
            isEnabled: false,
            holdHotkey: SpeechInputSettings.defaults.holdHotkey,
            selectedModelID: "missing",
            keepModelWarm: false,
            insertTrailingSpace: true
        )
        #expect(settings.selectedModel(in: SpeechModelRegistryResources.fallbackModels).id == SpeechInputModel.defaultID)
    }

    @Test("trailing space is added only after non punctuation")
    func trailingSpacePolicy() {
        let policy = SpeechInsertionPolicy(insertTrailingSpace: true)
        #expect(policy.preparedText(" hello ") == "hello ")
        #expect(policy.preparedText("hello.") == "hello.")
    }

    @Test("hotkey matcher requires exact press modifiers and key-only release")
    func hotkeyMatcher() throws {
        let matcher = SpeechHotkeyMatcher(combo: KeyCombo(key: KeyCombo.spaceKey, command: true, shift: true))
        let press = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))
        let release = try #require(NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))
        #expect(matcher.matchesPress(press))
        #expect(matcher.matchesRelease(release))
    }


    @Test("required modifiers allow key release fallback")
    func requiredModifierFallback() {
        let combo = KeyCombo(key: "v", command: true, shift: true)
        #expect(combo.requiredModifiersArePressed(in: [.command, .shift, .option]))
        #expect(!combo.requiredModifiersArePressed(in: [.command]))
    }

    @Test("model task initial progress matches task kind")
    func modelTaskInitialProgress() {
        #expect(SpeechModelTaskKind.download.initialProgress == .starting)
        #expect(SpeechModelTaskKind.prepare.initialProgress == .preparing)
    }

    @Test("cache state distinguishes missing partial and ready")
    func cacheStateDetection() {
        let baseURL = URL(fileURLWithPath: "/tmp/speech-cache")
        let files = ["a", "b"]
        #expect(SpeechModelCacheState.state(requiredFiles: files, baseURL: baseURL) { _ in false } == .missing)
        #expect(SpeechModelCacheState.state(requiredFiles: files, baseURL: baseURL) { url in
            url.lastPathComponent == "a"
        } == .partial)
        #expect(SpeechModelCacheState.state(requiredFiles: files, baseURL: baseURL) { url in
            url == baseURL || files.contains(url.lastPathComponent)
        } == .ready)
    }

    @Test("download status exposes progress details")
    func downloadStatusProgress() {
        let progress = SpeechDownloadProgress(fraction: 0.42, phaseTitle: "Downloading file 2 of 4")
        let status = SpeechInputStatus.downloading(progress)
        #expect(status.title == "Downloading model · 42%")
        #expect(status.progress == progress)
        #expect(!status.allowsModelActions)
    }

}
