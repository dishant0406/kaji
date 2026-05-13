import SwiftUI

struct EditorStatusBar: View {
    @Bindable var state: EditorTabState
    @State private var settings = EditorSettings.shared

    var body: some View {
        HStack(spacing: 12) {
            fileState
            Spacer(minLength: 12)
            statusItem("Ln \(state.cursorLine), Col \(state.cursorColumn)")
            if state.cursorPosition.selectionLength > 0 {
                statusItem("\(state.cursorPosition.selectionLength) selected")
            }
            statusItem("Spaces: \(settings.tabSize)")
            statusItem(state.languageDisplayName)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(KajiTheme.chrome)
        .overlay(Rectangle().fill(KajiTheme.border).frame(height: 1), alignment: .top)
    }

    private var fileState: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.isModified ? KajiTheme.diffHunkFg : KajiTheme.diffAddFg)
                .frame(width: 6, height: 6)
            Text(state.isSaving ? "Saving" : state.isModified ? "Unsaved" : "Saved")
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fgMuted)
        }
    }

    private func statusItem(_ text: String) -> some View {
        Text(text)
            .kajiFont(size: 11)
            .foregroundStyle(KajiTheme.fgMuted)
            .lineLimit(1)
    }
}
