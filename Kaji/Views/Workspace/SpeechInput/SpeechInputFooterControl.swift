import SwiftUI

struct SpeechInputFooterControl: View {
    @State private var store = SpeechInputSettingsStore.shared
    @State private var controller = SpeechInputController.shared
    @State private var hovered = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openSpeechToTextSettings, object: nil)
        } label: {
            SpeechInputFooterIcon(state: visualState, active: active)
                .frame(width: 28, height: 28)
                .background(background)
                .overlay(border)
                .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.borderless)
        .onHover { hovered = $0 }
        .kajiHoverEffect(isActive: active)
        .kajiChangeFeedback(KajiMotion.invalidFeedback, value: visualState.errorMessage ?? "", isEnabled: visualState.isFailed)
        .kajiPointer()
        .help(visualState.helpText(hotkey: store.settings.holdHotkey.displayString))
        .accessibilityLabel("Speech to Text")
        .accessibilityValue(visualState.accessibilityValue)
    }

    private var visualState: SpeechInputFooterVisualState {
        SpeechInputFooterVisualState.resolve(status: controller.status, isEnabled: store.settings.isEnabled)
    }

    private var background: some View {
        KajiControlSurface(base: active ? KajiTheme.surface : .clear, cornerRadius: KajiShape.tileRadius, isInteractive: true)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: KajiShape.tileRadius)
            .strokeBorder(KajiTheme.border.opacity(borderOpacity), lineWidth: 1)
    }

    private var active: Bool {
        hovered || visualState.isActive
    }

    private var borderOpacity: Double {
        ChromeIconButtonStylePolicy.borderOpacity(active: active, isTahoe: isTahoe)
    }

    private var isTahoe: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}
