import Foundation

enum AIGatewaySetupPrimaryAction: Equatable {
    case setupAndStart
    case stop
}

struct AIGatewaySetupPlan: Equatable {
    let title: String
    let detail: String
    let primaryTitle: String
    let primaryAction: AIGatewaySetupPrimaryAction
    let canRunPrimary: Bool
}

enum AIGatewaySetupPlanner {
    static func plan(
        settings: AIGatewaySettings,
        status: AIGatewayRuntimeStatus,
        installState: AIGatewayInstallState,
        validationMessage: String?,
        isWorking: Bool
    ) -> AIGatewaySetupPlan {
        if let validationMessage {
            return AIGatewaySetupPlan(
                title: "Setup incomplete",
                detail: validationMessage,
                primaryTitle: "Set Up",
                primaryAction: .setupAndStart,
                canRunPrimary: false
            )
        }
        if isWorking {
            return AIGatewaySetupPlan(
                title: "Working",
                detail: "Kaji is applying the gateway setup.",
                primaryTitle: "Working",
                primaryAction: .setupAndStart,
                canRunPrimary: false
            )
        }
        if case let .needsRepair(reason) = installState {
            return AIGatewaySetupPlan(
                title: "Update required",
                detail: reason,
                primaryTitle: "Update & Restart",
                primaryAction: .setupAndStart,
                canRunPrimary: true
            )
        }
        if !isInstalled(installState) {
            return AIGatewaySetupPlan(
                title: "Not installed",
                detail: "Kaji will install Claude Code Router and start the local gateway.",
                primaryTitle: "Set Up",
                primaryAction: .setupAndStart,
                canRunPrimary: true
            )
        }
        if case let .failed(message) = status {
            return AIGatewaySetupPlan(
                title: "Needs attention",
                detail: message,
                primaryTitle: "Fix & Restart",
                primaryAction: .setupAndStart,
                canRunPrimary: true
            )
        }
        if case .running = status {
            return AIGatewaySetupPlan(
                title: "Running",
                detail: "New Kaji terminals can use the gateway automatically.",
                primaryTitle: "Apply & Restart",
                primaryAction: .setupAndStart,
                canRunPrimary: true
            )
        }
        if settings.isEnabled {
            return AIGatewaySetupPlan(
                title: "Ready",
                detail: "The gateway is configured but not running.",
                primaryTitle: "Start",
                primaryAction: .setupAndStart,
                canRunPrimary: true
            )
        }
        return AIGatewaySetupPlan(
            title: "Off",
            detail: "Choose a provider, then let Kaji configure and start the gateway.",
            primaryTitle: "Set Up",
            primaryAction: .setupAndStart,
            canRunPrimary: true
        )
    }

    private static func isInstalled(_ state: AIGatewayInstallState) -> Bool {
        if case .installed = state { return true }
        return false
    }
}
