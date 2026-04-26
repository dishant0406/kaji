import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 0) {
            WindowDragRepresentable()
                .frame(height: 38)
            Spacer()
            VStack(spacing: 8) {
                DroidIcon(systemName: "folder", size: 20)
                    .foregroundStyle(DroidTheme.fgDim)
                Text("Select a project")
                    .droidFont(size: 14, weight: .semibold)
                    .foregroundStyle(DroidTheme.fg)
                Text("Use the sidebar to open a repository and start working.")
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fgDim)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
