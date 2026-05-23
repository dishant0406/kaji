import AppKit
import SwiftUI

struct ImageFilePreviewView: View {
    let url: URL
    @State private var scale: CGFloat = 1

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                ZStack(alignment: .topTrailing) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: image.size.width * scale, height: image.size.height * scale)
                            .padding(32)
                    }
                    zoomControls
                }
                .background(KajiTheme.bg)
            } else {
                QuickLookFilePreviewView(url: url)
            }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            zoomButton("minus.magnifyingglass") { scale = max(0.25, scale - 0.25) }
            zoomButton("1.magnifyingglass") { scale = 1 }
            zoomButton("plus.magnifyingglass") { scale = min(5, scale + 0.25) }
        }
        .padding(8)
    }

    private func zoomButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            KajiIcon(systemName: symbol, size: 12)
                .frame(width: 28, height: 26)
                .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
    }
}
