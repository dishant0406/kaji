import Foundation

public enum ClosedLidMode: String, Codable, Sendable, CaseIterable {
    case standard
    case powerProtect
}

public enum ClosedLidSafetyStopReason: String, Codable, Hashable, Sendable {
    case durationExpired
    case batteryBelowFloor
    case externalPowerDisconnected
    case lowPowerModeEnabled
    case thermalPressure
    case heartbeatLost
    case monitorFailure
}

public enum ClosedLidSessionStatus: Codable, Sendable, Equatable {
    case unavailable
    case off
    case arming
    case activeStandard
    case activePowerProtect
    case restoring
    case safetyStopped(ClosedLidSafetyStopReason)
    case failed(String)
}

public struct ClosedLidSafetySettings: Codable, Sendable, Equatable {
    public var durationMinutes: Int
    public var batteryFloorPercent: Int
    public var onlyWhileCharging: Bool
    public var stopOnLowPowerMode: Bool
    public var stopOnThermalPressure: Bool

    public init(
        durationMinutes: Int = 60,
        batteryFloorPercent: Int = 20,
        onlyWhileCharging: Bool = false,
        stopOnLowPowerMode: Bool = true,
        stopOnThermalPressure: Bool = true
    ) {
        self.durationMinutes = min(max(durationMinutes, 1), 1440)
        self.batteryFloorPercent = min(max(batteryFloorPercent, 5), 50)
        self.onlyWhileCharging = onlyWhileCharging
        self.stopOnLowPowerMode = stopOnLowPowerMode
        self.stopOnThermalPressure = stopOnThermalPressure
    }
}

public enum ClosedLidStandardCompatibility: String, Codable, Sendable, Equatable {
    case unavailable
    case needsVerification
    case verified
}

public struct ClosedLidHardwareIdentity: Codable, Hashable, Sendable {
    public let model: String
    public let osMajor: Int
    public let osMinor: Int
    public let osBuild: String

    public init(model: String, osMajor: Int, osMinor: Int, osBuild: String) {
        self.model = String(model.prefix(128))
        self.osMajor = osMajor
        self.osMinor = osMinor
        self.osBuild = String(osBuild.prefix(128))
    }

    public var attestationKey: String {
        let value = "\(model)|\(osMajor).\(osMinor)|\(osBuild)"
        return Data(value.utf8).base64EncodedString()
    }
}
