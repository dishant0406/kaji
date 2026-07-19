import KajiPowerHelperProtocol

struct ClosedLidPowerProtectPresentation: Equatable {
    let status: String
    let isReadyToStart: Bool

    static func resolve(_ state: PowerHelperRegistrationState) -> Self {
        switch state {
        case .unavailable:
            .init(status: "unavailable", isReadyToStart: false)
        case .notRegistered:
            .init(status: "helper not installed", isReadyToStart: false)
        case .requiresApproval:
            .init(status: "helper approval required", isReadyToStart: false)
        case .registering:
            .init(status: "helper registering", isReadyToStart: false)
        case let .ready(sleepDisabled):
            .init(status: sleepDisabled ? "SleepDisabled is live" : "helper ready", isReadyToStart: !sleepDisabled)
        case .failed:
            .init(status: "helper needs repair", isReadyToStart: false)
        }
    }
}
