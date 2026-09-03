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
        .kajiPointer()
        .help("Kaji")
        .accessibilityLabel("Kaji")
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

            Text("Kaji")
                .kajiFont(size: 12, weight: selected ? .semibold : .medium)
                .foregroundStyle(selected || hovered ? KajiTheme.fg : KajiTheme.fgMuted)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(background, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
    }

    @ViewBuilder
    private var iconImage: some View {
        if let image = Self.logoImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .opacity(selected || hovered ? 1 : 0.82)
        } else {
            Color.clear
        }
    }

    private var background: Color {
        if selected {
            return KajiTheme.surfaceMuted
        }
        if hovered {
            return KajiTheme.hover
        }
        return .clear
    }

    private static var logoImage: NSImage? {
        Bundle.appResources.url(
            forResource: "icon_512",
            withExtension: "png",
            subdirectory: "Assets.xcassets/AppIcon.appiconset"
        ).flatMap(NSImage.init(contentsOf:))
    }
}
