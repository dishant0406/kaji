import AppKit
import SwiftUI

struct ExternalIDEAppIcon: View {
    let path: String
    let size: CGFloat

    var body: some View {
        if let image = ExternalIDEAppIconCache.shared.image(for: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

@MainActor
private final class ExternalIDEAppIconCache {
    static let shared = ExternalIDEAppIconCache()

    private var images: [String: NSImage] = [:]

    func image(for path: String) -> NSImage? {
        if let image = images[path] {
            return image
        }
        let image = NSWorkspace.shared.icon(forFile: path)
        guard !image.representations.isEmpty else { return nil }
        images[path] = image
        return image
    }
}
