import SwiftUI

struct MonacoEditorLoadingOverlay: View {
    let isLoadingFile: Bool

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(isLoadingFile ? "Loading file..." : "Preparing editor...")
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KajiTheme.bg)
        .allowsHitTesting(false)
    }
}
