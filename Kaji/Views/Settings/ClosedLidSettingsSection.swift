import ClosedLidCore
import KajiPowerHelperProtocol
import ServiceManagement
import SwiftUI

struct ClosedLidStatusPresentation: Equatable {
    let title: String
    let detail: String
    let annotation: String
    let colorRole: ColorRole
    let canStart: Bool
    let canRestore: Bool

    enum ColorRole: Equatable {
        case neutral
        case active
        case warning
        case failure
    }

    static func resolve(_ status: ClosedLidSessionStatus) -> Self {
        switch status {
        case .unavailable:
            .init(
                title: "Closed-lid sessions unavailable",
                detail: "Run the capability probe or configure Power Protect to continue.",
                annotation: "Unavailable",
                colorRole: .warning,
                canStart: false,
                canRestore: false
            )
        case .off:
            .init(
                title: "Closed-lid sessions are off",
                detail: "Normal lid-close sleep is enabled.",
                annotation: "Off",
                colorRole: .neutral,
                canStart: true,
                canRestore: false
            )
        case .arming:
            .init(
                title: "Arming fail-safe protection",
                detail: "Keep the lid open until live verification completes.",
                annotation: "Arming",
                colorRole: .warning,
                canStart: false,
                canRestore: true
            )
        case .activeStandard:
            .init(
                title: "Standard session is live",
                detail: "Selector 12 and the external continuity guard are responding.",
                annotation: "Live · Standard",
                colorRole: .active,
                canStart: false,
                canRestore: true
            )
        case .activePowerProtect:
            .init(
                title: "Power Protect is live",
                detail: "The helper verified SleepDisabled. All automatic system sleep is disabled.",
                annotation: "Live · Power Protect",
                colorRole: .active,
                canStart: false,
                canRestore: true
            )
        case .restoring:
            .init(
                title: "Restoring normal sleep",
                detail: "Waiting for live confirmation before this session is considered off.",
                annotation: "Restoring",
                colorRole: .warning,
                canStart: false,
                canRestore: true
            )
        case let .safetyStopped(reason):
            .init(
                title: "Safety stop restored normal sleep",
                detail: safetyDetail(reason),
                annotation: "Safety stopped",
                colorRole: .warning,
                canStart: true,
                canRestore: false
            )
        case let .failed(message):
            .init(
                title: "Closed-lid session failed",
                detail: message,
                annotation: "Needs attention",
                colorRole: .failure,
                canStart: false,
                canRestore: true
            )
        }
    }

    private static func safetyDetail(_ reason: ClosedLidSafetyStopReason) -> String {
        switch reason {
        case .durationExpired:
            "The duration limit was reached."
        case .batteryBelowFloor:
            "Battery reached the configured safety floor."
        case .externalPowerDisconnected:
            "External power was disconnected."
        case .lowPowerModeEnabled:
            "Low Power Mode became active."
        case .thermalPressure:
            "macOS reported serious thermal pressure."
        case .heartbeatLost:
            "The fail-safe heartbeat stopped responding."
        case .monitorFailure:
            "A safety reading could not be verified, so the session stopped."
        }
    }
}

struct ClosedLidSettingsSection: View {
    @State private var controller = ClosedLidSessionController.shared
    @State private var helper = PowerProtectManager.shared
    @State private var compatibilityTest = ClosedLidCompatibilityTestController.shared
    @State private var selectedMode = ClosedLidMode.standard

    var body: some View {
        SettingsSection(
            "Closed-lid Sessions",
            footer: "Standard remains Experimental until this Mac and OS build pass the physical test. "
                + "Power Protect disables every automatic sleep path. "
                + "Never use either mode in an enclosed bag or under heavy load.",
            showsDivider: false
        ) {
            sessionStatusRow
            helperStatusRow
            SettingsDetailPickerRow(
                label: "Session mode",
                detail: selectedModeDetail,
                options: modeOptions,
                selection: $selectedMode
            )
            SettingsSliderRow(
                label: "Maximum duration",
                value: durationBinding,
                range: 1 ... 1440,
                valueWidth: 72,
                valueText: durationText
            )
            SettingsSliderRow(
                label: "Battery safety floor",
                value: batteryFloorBinding,
                range: 5 ... 50,
                valueText: { "\(Int($0.rounded()))%" }
            )
            SettingsDetailToggleRow(
                label: "Only while connected to power",
                detail: "Restore normal sleep immediately if the power adapter is disconnected.",
                isOn: settingsBinding(\.onlyWhileCharging)
            )
            SettingsDetailToggleRow(
                label: "Stop on Low Power Mode",
                detail: "Treat Low Power Mode as a request to restore normal sleep.",
                isOn: settingsBinding(\.stopOnLowPowerMode)
            )
            SettingsDetailToggleRow(
                label: "Stop on thermal pressure",
                detail: "Restore on serious or critical macOS thermal pressure.",
                isOn: settingsBinding(\.stopOnThermalPressure)
            )
            compatibilityTestRow
        }
        .task {
            await controller.probeCapability()
            await helper.probeCapability()
            await controller.refresh()
        }
        .onDisappear {
            guard compatibilityTest.state == .arming
                || compatibilityTest.state == .awaitingClose
                || compatibilityTest.state == .evaluating
            else { return }
            Task { await compatibilityTest.cancel() }
        }
    }

    private var sessionStatusRow: some View {
        let presentation = ClosedLidStatusPresentation.resolve(controller.status)
        return SettingsStatusActionRow(
            icon: "laptopcomputer",
            label: presentation.title,
            detail: presentation.detail,
            status: presentation.annotation,
            statusColor: color(presentation.colorRole)
        ) {
            if presentation.canRestore {
                Button("Restore Sleep") { Task { await controller.stop() } }
                    .buttonStyle(KajiButtonStyle(.danger, size: .small))
            }
            if presentation.canStart {
                Button(startTitle) { Task { await controller.start(mode: selectedMode) } }
                    .buttonStyle(KajiButtonStyle(.primary, size: .small))
                    .disabled(!selectedModeIsReady)
            } else if !presentation.canRestore {
                Button("Probe Again") { Task { await refreshAll() } }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
        }
    }

    private var helperStatusRow: some View {
        SettingsStatusActionRow(
            icon: "lock.shield",
            label: "Power Protect helper",
            detail: helperDetail,
            status: helperAnnotation,
            statusColor: helperColor
        ) {
            switch helper.state {
            case .notRegistered,
                 .failed:
                Button("Install or Repair") { Task { await helper.register() } }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            case .requiresApproval:
                Button("Open System Settings") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            case .unavailable,
                 .registering:
                Button("Refresh") { Task { await helper.refresh() } }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(helper.state == .registering)
            case .ready:
                Button("Refresh") { Task { await helper.refresh() } }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                Button("Uninstall") { Task { try? await helper.unregister() } }
                    .buttonStyle(KajiButtonStyle(.danger, size: .small))
            }
        }
    }

    private var compatibilityTestRow: some View {
        SettingsStatusActionRow(
            icon: "checkmark.shield",
            label: "Standard compatibility test",
            detail: compatibilityTest.detail,
            status: compatibilityAnnotation,
            statusColor: compatibilityColor
        ) {
            switch compatibilityTest.state {
            case .idle,
                 .failed:
                Button("Run Probe") { Task { await compatibilityTest.probe() } }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            case .probing:
                Button("Cancel") { Task { await compatibilityTest.cancel() } }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            case .ready:
                Button("Start Physical Test") { Task { await compatibilityTest.arm() } }
                    .buttonStyle(KajiButtonStyle(.primary, size: .small))
            case .arming,
                 .evaluating,
                 .cancelling:
                Button("Force Restore") { Task { await compatibilityTest.cancel() } }
                    .buttonStyle(KajiButtonStyle(.danger, size: .small))
            case .awaitingClose:
                Button("Cancel & Restore") { Task { await compatibilityTest.cancel() } }
                    .buttonStyle(KajiButtonStyle(.danger, size: .small))
                Button("Evaluate") { Task { await compatibilityTest.evaluate() } }
                    .buttonStyle(KajiButtonStyle(.primary, size: .small))
                    .disabled(!compatibilityTest.canEvaluate)
            case .passed:
                Button("Test Again") { Task { await compatibilityTest.probe() } }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
        }
    }

    private var modeOptions: [KajiSelectOption<ClosedLidMode>] {
        [
            .init(id: ClosedLidMode.standard.rawValue, title: "Standard · Experimental", value: .standard),
            .init(id: ClosedLidMode.powerProtect.rawValue, title: "Power Protect", value: .powerProtect),
        ]
    }

    private var selectedModeDetail: String {
        switch selectedMode {
        case .standard:
            "Uses private selector 12 with an external fail-safe guard. Verification applies only to this hardware and OS build."
        case .powerProtect:
            "Uses a privileged helper and the global SleepDisabled setting. "
                + "Apple menu sleep and other automatic sleep paths are disabled too."
        }
    }

    private var startTitle: String {
        selectedMode == .standard ? "Start Standard" : "Start Power Protect"
    }

    private var selectedModeIsReady: Bool {
        switch selectedMode {
        case .standard:
            return controller.selectorCapability?.isAvailable == true
        case .powerProtect:
            if case .ready(sleepDisabled: false) = helper.state { return true }
            return false
        }
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { Double(controller.settings.durationMinutes) },
            set: { value in updateSettings { $0.durationMinutes = Int(value.rounded()) } }
        )
    }

    private var batteryFloorBinding: Binding<Double> {
        Binding(
            get: { Double(controller.settings.batteryFloorPercent) },
            set: { value in updateSettings { $0.batteryFloorPercent = Int(value.rounded()) } }
        )
    }

    private func settingsBinding(_ keyPath: WritableKeyPath<ClosedLidSafetySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { controller.settings[keyPath: keyPath] },
            set: { value in updateSettings { $0[keyPath: keyPath] = value } }
        )
    }

    private func updateSettings(_ change: (inout ClosedLidSafetySettings) -> Void) {
        var settings = controller.settings
        change(&settings)
        controller.updateSettings(settings)
    }

    private func durationText(_ value: Double) -> String {
        let minutes = Int(value.rounded())
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    private var helperDetail: String {
        switch helper.state {
        case .unavailable:
            "The privileged helper is unavailable on this Mac."
        case .notRegistered:
            "Install the least-privilege helper to use Power Protect."
        case .requiresApproval:
            "Approve the helper in System Settings, then refresh."
        case .registering:
            "Registering the privileged helper…"
        case let .ready(sleepDisabled):
            sleepDisabled
                ? "Live verification reports SleepDisabled is active."
                : "Helper ready; live verification reports normal sleep is enabled."
        case let .failed(message):
            message
        }
    }

    private var helperAnnotation: String {
        switch helper.state {
        case .unavailable: "Unavailable"
        case .notRegistered: "Not installed"
        case .requiresApproval: "Approval required"
        case .registering: "Registering"
        case let .ready(sleepDisabled): sleepDisabled ? "SleepDisabled live" : "Ready"
        case .failed: "Needs repair"
        }
    }

    private var helperColor: Color {
        switch helper.state {
        case .ready(sleepDisabled: true): KajiTheme.diffAddFg
        case .failed: KajiTheme.diffRemoveFg
        case .requiresApproval,
             .registering: KajiTheme.diffHunkFg
        case .unavailable,
             .notRegistered,
             .ready: KajiTheme.fgDim
        }
    }

    private var compatibilityAnnotation: String {
        switch compatibilityTest.state {
        case .idle: controller.standardCompatibility == .verified ? "Verified" : "Not verified"
        case .probing: "Probing"
        case .ready: "Ready"
        case .arming: "Arming"
        case .awaitingClose: "Guard live"
        case .evaluating: "Evaluating"
        case .passed: "Verified"
        case .failed: "Not verified"
        case .cancelling: "Restoring"
        }
    }

    private var compatibilityColor: Color {
        switch compatibilityTest.state {
        case .passed: KajiTheme.diffAddFg
        case .failed: KajiTheme.diffRemoveFg
        case .arming,
             .awaitingClose,
             .evaluating,
             .cancelling: KajiTheme.diffHunkFg
        case .idle,
             .probing,
             .ready:
            controller.standardCompatibility == .verified ? KajiTheme.diffAddFg : KajiTheme.fgDim
        }
    }

    private func color(_ role: ClosedLidStatusPresentation.ColorRole) -> Color {
        switch role {
        case .neutral: KajiTheme.fgDim
        case .active: KajiTheme.diffAddFg
        case .warning: KajiTheme.diffHunkFg
        case .failure: KajiTheme.diffRemoveFg
        }
    }

    private func refreshAll() async {
        await controller.probeCapability()
        await helper.refresh()
        await controller.refresh()
    }
}
