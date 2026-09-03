import AppKit
import SwiftUI

struct SpeechToTextSettingsView: View {
    @State private var store = SpeechInputSettingsStore.shared
    @State private var controller = SpeechInputController.shared
    @State private var modelRegistry = SpeechModelRegistryStore.shared
    @State private var recordingShortcut = false

    var body: some View {
        SettingsContainer {
            SettingsSection("Speech to Text", footer: footerText) {
                SettingsToggleRow(label: "Enable", isOn: enableBinding)
                shortcutRow
                SettingsDetailToggleRow(
                    label: "Keep model warm",
                    detail: "Keeps the selected model in memory after first use for faster repeat dictation.",
                    isOn: binding(\.keepModelWarm)
                )
                SettingsToggleRow(label: "Insert trailing space", isOn: binding(\.insertTrailingSpace))
            }
            SpeechModelCatalogSection(
                models: modelRegistry.models,
                selectedID: store.settings.selectedModelID,
                status: controller.status,
                refreshToken: controller.cacheRefreshToken,
                onSelect: { controller.selectModel(id: $0) },
                onDownload: { runModelAction($0, action: controller.downloadSelectedModel) },
                onPrepare: { runModelAction($0, action: controller.prepareSelectedModel) },
                onRemove: { runModelAction($0, action: controller.removeSelectedModel) },
                onOpenJSON: { modelRegistry.openRegistryFile() },
                onReload: { controller.reloadModelRegistry() },
                registryError: modelRegistry.lastError
            )
            SettingsSection("Permissions") {
                SettingsRow("Microphone") { microphoneStatus }
            }
            SettingsSection("Status", showsDivider: false) {
                SettingsRow("Current state") { statusView }
            }
        }
    }

    private var footerText: String {
        "Hold the configured shortcut, speak, then release to insert text at the active cursor. " +
            "Audio and transcription stay local on this Mac."
    }

    private var shortcutRow: some View {
        SettingsRow("Hold shortcut") {
            if recordingShortcut {
                ShortcutRecorderView { combo in
                    store.update { $0.holdHotkey = combo }
                    recordingShortcut = false
                } onCancel: {
                    recordingShortcut = false
                }
                .frame(width: 170, height: 28)
                .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(KajiTheme.border, lineWidth: 1))
            } else {
                shortcutButton
            }
        }
    }

    private var shortcutButton: some View {
        Button { recordingShortcut = true } label: {
            Text(store.settings.holdHotkey.displayString)
                .kajiFont(size: 12, weight: .semibold, design: .monospaced)
                .foregroundStyle(KajiTheme.fg)
                .frame(width: 170, height: 28)
                .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(KajiTheme.border, lineWidth: 1))
        }
        .buttonStyle(.borderless)
        .kajiPointer()
    }

    private var microphoneStatus: some View {
        _ = controller.permissionRefreshToken
        let state = SpeechMicrophonePermissionState.current
        return HStack(spacing: 8) {
            Circle()
                .fill(state == .allowed ? KajiTheme.diffAddFg : KajiTheme.fgDim)
                .frame(width: 7, height: 7)
            Text(state.title)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
            if state == .notDetermined {
                SpeechSettingsButton("Request Access") { controller.requestMicrophonePermission() }
            }
            if state == .denied {
                SpeechSettingsButton("Open Settings") { openMicrophoneSettings() }
            }
        }
    }

    private var statusView: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(controller.status.title)
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(controller.status.isActive ? KajiTheme.accent : KajiTheme.fgMuted)
            if let progress = controller.status.progress {
                SpeechDownloadProgressView(progress: progress)
            }
        }
    }

    private var enableBinding: Binding<Bool> {
        Binding(get: { store.settings.isEnabled }, set: { controller.setEnabled($0) })
    }

    private func binding(_ keyPath: WritableKeyPath<SpeechInputSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in store.update { $0[keyPath: keyPath] = value } })
    }

    private func runModelAction(_ model: SpeechInputModel, action: () -> Void) {
        if store.settings.selectedModelID != model.id {
            controller.selectModel(id: model.id)
        }
        action()
    }

    private func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}
