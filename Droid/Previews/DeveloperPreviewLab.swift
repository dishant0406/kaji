import SwiftUI

@MainActor
private struct DeveloperPreviewLab: View {
    private let stores = PreviewStores.make()
    @State private var showAIUsagePopover = false

    init() {
        UserDefaults.standard.register(defaults: ["droid.sidebarExpanded": true])
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(
                showAIUsagePopover: $showAIUsagePopover
            )
                .environment(stores.appState)
                .environment(stores.projectStore)
                .environment(stores.worktreeStore)
                .frame(width: SidebarLayout.expandedWidth)

            Rectangle()
                .fill(DroidTheme.border)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 18) {
                Text("Developer Preview")
                    .droidFont(size: 28, weight: .semibold)
                Text("Use this canvas for fast SwiftUI iteration while the real Droid app runs from start.sh.")
                    .droidFont(size: 14)
                    .foregroundStyle(DroidTheme.fgMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
            .background(DroidTheme.bg)
        }
        .frame(width: 1100, height: 720)
        .environment(AppTypographySettings.shared)
        .preferredColorScheme(DroidTheme.colorScheme)
        .background(DroidTheme.bg)
    }
}

#Preview("Workspace Shell") {
    DeveloperPreviewLab()
}

#Preview("Settings") {
    SettingsView()
        .environment(AppTypographySettings.shared)
        .preferredColorScheme(DroidTheme.colorScheme)
}
