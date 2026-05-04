import AppKit
import SwiftUI

struct ParentAgentTabButton: View {
    static let size: CGFloat = 36

    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
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
            .frame(width: Self.size, height: Self.size)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Parent Agent")
        .accessibilityLabel("Parent Agent")
    }

    private static var logoImage: NSImage? {
        Bundle.module.url(
            forResource: "icon_512",
            withExtension: "png",
            subdirectory: "Assets.xcassets/AppIcon.appiconset"
        ).flatMap(NSImage.init(contentsOf:))
    }
}
