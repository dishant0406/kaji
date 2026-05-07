import SwiftUI

enum GeneralSettingsKeys {
    static let autoExpandWorktreesOnProjectSwitch = "droid.general.autoExpandWorktreesOnProjectSwitch"
    static let footerTerminalEnabled = "droid.general.footerTerminalEnabled"
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

            SettingsSection(
                "Power",
                footer: "The battery lid-close override uses administrator permission and changes a system-wide pmset setting.",
                showsDivider: false
            ) {
                SettingsDetailToggleRow(
                    label: "Prevent system sleep",
                    detail: sleepPrevention.detail,
                    isOn: Binding(
                        get: { sleepPrevention.isEnabled },
                        set: { sleepPrevention.setEnabled($0) }
                    )
                )
                SettingsDetailToggleRow(
                    label: "Prevent battery lid-close sleep",
                    detail: sleepPrevention.batteryLidCloseDetail,
                    isOn: Binding(
                        get: { sleepPrevention.isBatteryLidCloseEnabled },
                        set: { sleepPrevention.setBatteryLidCloseEnabled($0) }
                    )
                )
            }
        }
    }
}
