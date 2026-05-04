import AppKit
import SwiftUI

struct ParentAgentTabButton: View {
    static let size: CGFloat = 36

    let selected: Bool
    var expanded = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            if expanded {
                expandedLayout
            } else {
                collapsedLayout
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Droid")
        .accessibilityLabel("Droid")
    }

    private var collapsedLayout: some View {
        iconImage
            .frame(width: Self.size, height: Self.size)
            .clipped()
            .contentShape(Rectangle())
    }

    private var expandedLayout: some View {
        HStack(spacing: 10) {
            iconImage
                .frame(width: 28, height: 28)
                .clipped()

            Text("Droid")
                .droidFont(size: 12, weight: selected ? .semibold : .medium)
                .foregroundStyle(selected || hovered ? DroidTheme.fg : DroidTheme.fgMuted)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(background, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        .contentShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
    }

    private var iconImage: some View {
        Group {
            if let image = Self.logoImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .opacity(selected || hovered ? 1 : 0.82)
            } else {
                Color.clear
            }
        }
    }

    private var background: Color {
        if selected { return DroidTheme.surfaceMuted }
        if hovered { return DroidTheme.hover }
        return .clear
    }

    private static var logoImage: NSImage? {
        Bundle.module.url(
            forResource: "icon_512",
            withExtension: "png",
            subdirectory: "Assets.xcassets/AppIcon.appiconset"
        ).flatMap(NSImage.init(contentsOf:))
    }
}
