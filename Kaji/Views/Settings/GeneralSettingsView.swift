import SwiftUI

enum GeneralSettingsKeys {
    static let autoExpandWorktreesOnProjectSwitch = "kaji.general.autoExpandWorktreesOnProjectSwitch"
    static let footerTerminalEnabled = "kaji.general.footerTerminalEnabled"
}

struct GeneralSettingsView: View {
    @State private var sleepPrevention = SleepPreventionController.shared

    @AppStorage(GeneralSettingsKeys.autoExpandWorktreesOnProjectSwitch)
    private var autoExpandWorktrees = false
    @AppStorage(TabCloseConfirmationPreferences.confirmRunningProcessKey)
    private var confirmRunningProcess = true
    @AppStorage(ProjectLifecyclePreferences.keepOpenWhenNoTabsKey)
    private var keepProjectsOpenWhenNoTabs = false
    @AppStorage(GeneralSettingsKeys.footerTerminalEnabled)
    private var footerTerminalEnabled = true

    var body: some View {
        SettingsContainer {
            SettingsSection(
                "Sidebar",
                footer: "Automatically reveal worktrees when you switch to a project."
            ) {
                SettingsToggleRow(
                    label: "Auto-expand worktrees on project switch",
                    isOn: $autoExpandWorktrees
                )
            }

            SettingsSection(
                "Projects",
                footer: "Keep projects in the sidebar after closing their last tab. "
                    + "To remove a project afterward, use the right-click menu."
            ) {
                SettingsToggleRow(
                    label: "Keep projects open after closing the last tab",
                    isOn: $keepProjectsOpenWhenNoTabs
                )
            }

            SettingsSection("Tabs") {
                SettingsToggleRow(
                    label: "Confirm before closing a tab with a running process",
                    isOn: $confirmRunningProcess
                )
            }

            SettingsSection(
                "Footer Terminal",
                footer: "Shows the footer terminal chevron and enables the toggle shortcut."
            ) {
                SettingsToggleRow(
                    label: "Show footer terminal toggle",
                    isOn: $footerTerminalEnabled
                )
            }

            KajiCLICommandSettingsSection()

            SettingsSection(
                "Power",
                footer: "Idle sleep prevention uses a separate verified macOS power assertion. It does not change lid-close behavior.",
                showsDivider: true
            ) {
                SettingsDetailToggleRow(
                    label: "Prevent idle sleep",
                    detail: sleepPrevention.detail,
                    isOn: Binding(
                        get: { sleepPrevention.isEnabled },
                        set: { sleepPrevention.setEnabled($0) }
                    )
                )
            }

            ClosedLidSettingsSection()
        }
    }
}
