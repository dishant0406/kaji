import SwiftUI

struct KeyboardShortcutRow: View {
    let action: ShortcutAction
    var displayName: String?
    let combo: KeyCombo
    let isRecording: Bool
    let conflictAction: ShortcutAction?
    let onStartRecording: () -> Void
    let onRecord: (KeyCombo) -> Void
    let onCancel: () -> Void
    let onReset: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(displayName ?? action.displayName)
                    .kajiFont(size: SettingsMetrics.labelFontSize)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isRecording {
                    recordingView
                } else {
                    comboDisplay
                }
            }

            if let conflictAction {
                Text("Conflicts with \"\(conflictAction.displayName)\" - press a different shortcut or Esc to cancel")
                    .kajiFont(size: 10)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
        .background(hovered ? KajiTheme.surface : .clear)
        .onHover { hovered = $0 }
    }

    private var comboDisplay: some View {
        HStack(spacing: 6) {
            if hovered {
                Button(action: onReset) {
                    KajiIcon(systemName: "arrow.counterclockwise", size: 10)
                }
                .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                .accessibilityLabel("Reset Shortcut")
            }

            Button(action: onStartRecording) {
                Text(combo.displayString)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize, weight: .medium, design: .rounded)
            }
            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
        }
    }

    private var recordingView: some View {
        ZStack {
            ShortcutRecorderView(onRecord: onRecord, onCancel: onCancel)
                .frame(width: 0, height: 0)
                .opacity(0)

            Text("Press shortcut...")
                .kajiFont(size: SettingsMetrics.footnoteFontSize, weight: .medium)
                .foregroundStyle(KajiTheme.diffHunkFg)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(KajiTheme.diffHunkBg, in: RoundedRectangle(cornerRadius: 5))
        }
    }
}
