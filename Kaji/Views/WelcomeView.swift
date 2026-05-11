import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 0) {
            WindowDragRepresentable()
                .frame(height: 38)
            Spacer()
            VStack(spacing: 8) {
                KajiIcon(systemName: "folder", size: 20)
                    .foregroundStyle(KajiTheme.fgDim)
                Text("Select a project")
                    .kajiFont(size: 14, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Text("Use the sidebar to open a repository and start working.")
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
