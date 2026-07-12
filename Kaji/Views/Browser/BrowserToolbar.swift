import SwiftUI

struct BrowserToolbar: View {
    @Binding var pendingURL: String
    @Binding var deviceProfileID: String
    let addressFocusVersion: Int
    let showsPageText: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onReload: () -> Void
    let onNavigate: () -> Void
    let onReadPage: () -> Void
    @FocusState private var addressFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            IconButton(symbol: "arrow.left", accessibilityLabel: "Back", action: onBack)
                .attachedShortcutHint(for: .browserBack)
            IconButton(symbol: "arrow.right", accessibilityLabel: "Forward", action: onForward)
                .attachedShortcutHint(for: .browserForward)
            IconButton(symbol: "arrow.clockwise", accessibilityLabel: "Reload", action: onReload)
                .attachedShortcutHint(for: .browserReload)
            TextField("Search or enter URL", text: $pendingURL)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(KajiControlSurface(base: KajiTheme.surface, cornerRadius: KajiShape.tileRadius))
                .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border.opacity(0.7), lineWidth: 1))
                .animation(KajiMotion.fast, value: pendingURL)
                .focused($addressFocused)
                .onSubmit { onNavigate() }
                .attachedShortcutHint(for: .browserFocusAddressBar)
            IconButton(symbol: "paperplane", accessibilityLabel: "Open URL", action: onNavigate)
                .attachedShortcutHint(label: "Enter", modifiers: 0, showWhenAnyModifierHeld: true)
            BrowserDeviceSelect(selection: $deviceProfileID)
                .help("Device mode")
            IconButton(symbol: "text.page", selected: showsPageText, accessibilityLabel: "Read Page", action: onReadPage)
                .help("Read page text")
                .attachedShortcutHint(for: .browserReadPage)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onChange(of: addressFocusVersion) { _, _ in
            addressFocused = true
        }
        .background(
            TranslucentSurface(
                base: KajiTheme.secondaryBackground,
                material: .headerView,
                tintOpacity: 0.44
            )
        )
    }
}
