import SwiftUI

@MainActor
private struct DeveloperPreviewLab: View {
    private let stores = PreviewStores.make()

    init() {
        UserDefaults.standard.register(defaults: ["kaji.sidebarExpanded": true])
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .environment(stores.appState)
                .environment(stores.projectStore)
                .environment(stores.worktreeStore)
                .frame(width: SidebarLayout.expandedWidth)

            Rectangle()
                .fill(KajiTheme.border)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 18) {
                Text("Developer Preview")
                    .kajiFont(size: 28, weight: .semibold)
                Text("Use this canvas for fast SwiftUI iteration while the real Kaji app runs from start.sh.")
                    .kajiFont(size: 14)
                    .foregroundStyle(KajiTheme.fgMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
            .background(KajiTheme.bg)
        }
        .frame(width: 1100, height: 720)
        .environment(AppTypographySettings.shared)
        .preferredColorScheme(KajiTheme.colorScheme)
        .background(KajiTheme.bg)
    }
}

#Preview("Workspace Shell") {
    DeveloperPreviewLab()
}

#Preview("Settings") {
    SettingsView()
        .environment(AppTypographySettings.shared)
        .preferredColorScheme(KajiTheme.colorScheme)
}
