import SwiftUI

struct AIUsageSettingsView: View {
    private let usageService = AIUsageService.shared
    @AppStorage(AIUsageSettingsStore.usageEnabledKey) private var usageEnabled = false
    @AppStorage(AIUsageSettingsStore.showSecondaryLimitsKey) private var showSecondaryLimits = AIUsageSettingsStore
        .defaultShowSecondaryLimits
    @State private var usageDisplayMode = AIUsageSettingsStore.usageDisplayMode()
    @State private var autoRefreshInterval = AIUsageSettingsStore.autoRefreshInterval()

    private var providers: [AIUsageProviderCatalogEntry] {
        AIUsageProviderCatalog.providers
    }

    var body: some View {
        ScrollView {
            SettingsContainer {
                SettingsSection(
                    "Usage Board",
                    footer: "Enable the AI usage board to show provider quotas and session tracking in the sidebar.",
                    showsDivider: usageEnabled
                ) {
                    SettingsToggleRow(label: "Enabled", isOn: $usageEnabled)
                }

                if usageEnabled {
                    displaySection
                    providersSection
                }
            }
        }
        .onChange(of: usageEnabled) { _, enabled in
            AIUsageSettingsStore.setUsageEnabled(enabled)
            if enabled {
                refreshUsage()
            }
        }
        .onChange(of: usageDisplayMode) { _, newValue in
            AIUsageSettingsStore.setUsageDisplayMode(newValue)
        }
        .onChange(of: autoRefreshInterval) { _, newValue in
            AIUsageSettingsStore.setAutoRefreshInterval(newValue)
        }
        .onChange(of: showSecondaryLimits) { _, _ in
            usageService.recomposeSnapshots()
        }
    }

    private var displaySection: some View {
        SettingsSection("Display") {
            SettingsRow("Show") {
                SegmentedPicker(
                    selection: $usageDisplayMode,
                    options: AIUsageDisplayMode.allCases.map { ($0, $0.label) }
                )
                .frame(width: 180)
            }

            SettingsRow("Auto Refresh") {
                DroidSelect(
                    options: AIUsageAutoRefreshInterval.allCases.map {
                        DroidSelectOption(id: "\($0.rawValue)", title: $0.label, value: $0)
                    },
                    selection: $autoRefreshInterval,
                    width: 110
                )
            }

            SettingsDetailToggleRow(
                label: "Show Secondary Limits",
                detail: "Display weekly and monthly quotas alongside the primary session usage.",
                isOn: $showSecondaryLimits
            )
        }
    }

    private var providersSection: some View {
        SettingsSection(
            "Providers",
            footer: "Choose which providers appear on the usage board.",
            showsDivider: false
        ) {
            SettingsRow("Refresh Data") {
                Button {
                    refreshUsage()
                } label: {
                    HStack(spacing: 6) {
                        DroidIcon(systemName: "arrow.clockwise", size: 10)
                        Text("Refresh")
                    }
                }
                .buttonStyle(DroidButtonStyle(.secondary, size: .small))
                .disabled(usageService.isRefreshing)
            }

            AIUsageProviderTrackingGrid(
                providers: providers,
                bindingForProvider: providerToggleBinding(for:)
            )
        }
    }

    private func providerToggleBinding(for provider: AIUsageProviderCatalogEntry) -> Binding<Bool> {
        Binding(
            get: {
                AIUsageProviderTrackingStore.isTracked(providerID: provider.id)
            },
            set: { isOn in
                AIUsageProviderTrackingStore.setTracked(isOn, providerID: provider.id)
                usageService.recomposeSnapshots()
            }
        )
    }

    private func refreshUsage() {
        Task {
            await usageService.refresh(force: true)
        }
    }
}
