import SwiftUI

struct BrowserToolbar: View {
    @Binding var pendingURL: String
    @Binding var deviceProfileID: String
    let showsPageText: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onReload: () -> Void
    let onNavigate: () -> Void
    let onOpenDevTools: () -> Void
    let onReadPage: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            IconButton(symbol: "arrow.left", accessibilityLabel: "Back", action: onBack)
            IconButton(symbol: "arrow.right", accessibilityLabel: "Forward", action: onForward)
            IconButton(symbol: "arrow.clockwise", accessibilityLabel: "Reload", action: onReload)
            TextField("Search or enter URL", text: $pendingURL)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
                .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border.opacity(0.7), lineWidth: 1))
                .animation(KajiMotion.fast, value: pendingURL)
                .onSubmit { onNavigate() }
            IconButton(symbol: "paperplane", accessibilityLabel: "Open URL", action: onNavigate)
            BrowserDeviceSelect(selection: $deviceProfileID)
                .help("Device mode")
            IconButton(symbol: "hammer", accessibilityLabel: "Open DevTools", action: onOpenDevTools)
                .help("Open Chromium DevTools")
            IconButton(symbol: "text.page", selected: showsPageText, accessibilityLabel: "Read Page", action: onReadPage)
                .help("Read page text")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(KajiTheme.secondaryBackground)
    }
}
