import SwiftUI

struct KajiLogo: View {
    let size: CGFloat

    var body: some View {
        if let image = logoImage {
            Image(nsImage: image)
                .resizable().scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.22)))
        } else {
            KajiIcon(systemName: "terminal", size: size)
                .foregroundStyle(KajiTheme.fgMuted)
                .frame(width: size, height: size)
        }
    }

    private var logoImage: NSImage? {
        Bundle.appResources.url(
            forResource: "icon_512",
            withExtension: "png",
            subdirectory: "Assets.xcassets/AppIcon.appiconset"
        ).flatMap(NSImage.init(contentsOf:)) ?? NSApplication.shared.applicationIconImage
    }
}
