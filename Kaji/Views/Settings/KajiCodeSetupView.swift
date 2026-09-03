import SwiftUI

struct KajiCodeSetupView: View {
    @State private var state = KajiCodeInstaller.state()
    @State private var launcherSettings = CLILauncherSettings.shared
    @State private var runtimeResolution: KajiCodeRuntimeResolution?
    @State private var refreshTask: Task<Void, Never>?
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        SettingsSection(
            "KajiCode",
            footer: "Kaji installs the latest compatible KajiCode release into Application Support "
                + "and configures hooks plus MCP registrations.",
            showsDivider: true
        ) {
            HStack(alignment: .center, spacing: 10) {
                CLILauncherIcon(iconName: "kaji", size: 16, color: KajiTheme.fg)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Managed CLI")
                        .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                    Text(statusText)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if case .installed = state {
                    Button("Uninstall", action: uninstall)
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                        .disabled(isWorking)
                }

                Button(primaryTitle, action: install)
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(isWorking)
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 2)
        }
        .task {
            await refreshRuntimeResolution()
        }
        .onChange(of: configuredCommand) { _, _ in
            scheduleRuntimeRefresh()
        }
    }

    private var primaryTitle: String {
        if isWorking {
            return "Setting up"
        }
        if runtimeResolution != nil, runtimeResolution?.source != .managed {
            return "Setup"
        }
        if case .installed = state {
            return "Update & Setup"
        }
        return "Install"
    }

    private var statusText: String {
        if let message {
            return message
        }
        switch state {
        case .missing:
            if runtimeResolution?.source == .developerOverride {
                return "Using developer override"
            }
            if runtimeResolution?.source == .path {
                return "External CLI found"
            }
            return "Not installed"
        case let .installed(manifest):
            return "Installed \(manifest.activeVersion) from \(manifest.platform)"
        case let .needsRepair(detail):
            return detail
        }
    }

    private var statusColor: Color {
        switch state {
        case .installed:
            KajiTheme.fgMuted
        case .missing,
             .needsRepair:
            runtimeResolution == nil ? KajiTheme.diffRemoveFg : KajiTheme.fgMuted
        }
    }

    private var configuredCommand: String {
        launcherSettings.command(for: "kajicode")
    }

    private func install() {
        isWorking = true
        message = "Setting up..."
        Task { @MainActor in
            let result = await KajiCodeSetupService.installOrUpdate(configuredCommand: configuredCommand)
            state = result.state
            message = result.message
            await refreshRuntimeResolution()
            isWorking = false
        }
    }

    private func uninstall() {
        isWorking = true
        message = "Uninstalling..."
        Task { @MainActor in
            let result = await KajiCodeSetupService.uninstall()
            state = result.state
            message = result.message
            runtimeResolution = nil
            isWorking = false
        }
    }

    private func scheduleRuntimeRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await refreshRuntimeResolution()
        }
    }

    private func refreshRuntimeResolution() async {
        let command = configuredCommand
        let resolution = await GitProcessRunner.offMain {
            KajiCodeRuntimeLocator.resolve(configuredCommand: command)
        }
        guard !Task.isCancelled else { return }
        runtimeResolution = resolution
    }
}
