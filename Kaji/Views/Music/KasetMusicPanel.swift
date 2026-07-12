import Kaset
import SwiftUI

struct KasetMusicPanel: View {
    let controller: KasetEmbeddedController
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(KajiTheme.border)
            KasetEmbeddedView(controller: controller, configuration: .sidePanel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(KajiTheme.bg)
        .clipped()
    }

    private var header: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: "music.note", size: 14)
                .foregroundStyle(KajiTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kaset")
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Text("YouTube Music")
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Spacer(minLength: 0)
            IconButton(symbol: "xmark", size: 11, accessibilityLabel: "Close Kaset") { onClose() }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(ChromeBackgroundSurface())
    }
}
