import ClosedLidCore
import Darwin
import Foundation
import KajiPowerHelperProtocol
import Observation

@MainActor @Observable
final class ClosedLidSessionController {
    static let shared = ClosedLidSessionController(safetyMonitor: ClosedLidSafetyMonitor())

    private enum Keys {
        static let safetySettings = "closedLid.safetySettings.v1"
        static let attestationPrefix = "closedLid.standardAttestation.v1."
    }

    private let defaults: UserDefaults
    private let standardSession: any ClosedLidStandardSessionManaging
    private let powerProtect: any PowerProtectManaging
    private let safetyMonitor: ClosedLidSafetyMonitor?
    private let hardwareIdentity: @Sendable () -> ClosedLidHardwareIdentity
    private var activeMode: ClosedLidMode?

    private(set) var status: ClosedLidSessionStatus = .off
    private(set) var selectorCapability: ClosedLidSelectorProbeResult?
    private(set) var standardCompatibility: ClosedLidStandardCompatibility = .unavailable
    private(set) var lastStandardEvidence: ClosedLidStandardSessionEvidence?
    var powerProtectState: PowerHelperRegistrationState { powerProtect.state }

    var requiresTerminationDrain: Bool {
        activeMode != nil || status == .arming || status == .restoring
    }

    var settings: ClosedLidSafetySettings {
        didSet {
            persistSettings()
            let updated = settings
            Task { await safetyMonitor?.update(settings: updated) }
        }
    }

    init(
        defaults: UserDefaults = .standard,
        standardSession: any ClosedLidStandardSessionManaging = ClosedLidStandardGuardClient.shared,
        powerProtect: any PowerProtectManaging = PowerProtectManager.shared,
        safetyMonitor: ClosedLidSafetyMonitor? = nil,
        hardwareIdentity: @escaping @Sendable () -> ClosedLidHardwareIdentity = ClosedLidSystemIdentity.current
    ) {
        self.defaults = defaults
        self.standardSession = standardSession
        self.powerProtect = powerProtect
        self.safetyMonitor = safetyMonitor
        self.hardwareIdentity = hardwareIdentity
        if let data = defaults.data(forKey: Keys.safetySettings),
           let decoded = try? JSONDecoder().decode(ClosedLidSafetySettings.self, from: data)
        {
            settings = ClosedLidSafetySettings(
                durationMinutes: decoded.durationMinutes,
                batteryFloorPercent: decoded.batteryFloorPercent,
                onlyWhileCharging: decoded.onlyWhileCharging,
                stopOnLowPowerMode: decoded.stopOnLowPowerMode,
                stopOnThermalPressure: decoded.stopOnThermalPressure
            )
        } else {
            settings = ClosedLidSafetySettings()
        }
        standardSession.onUnexpectedExit = { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.handleUnexpectedGuardExit() }
        }
    }

    func probeCapability() async {
        guard activeMode == nil, status != .arming, status != .restoring else { return }
        let result = await standardSession.probeCapability()
        await powerProtect.probeCapability()
        guard activeMode == nil, status != .arming, status != .restoring else { return }
        selectorCapability = result
        standardCompatibility = result.isAvailable
            ? (hasCurrentAttestation ? .verified : .needsVerification)
            : .unavailable
        if result.isAvailable || powerProtectState != .unavailable {
            status = .off
        } else {
            status = .unavailable
        }
    }

    func start(mode: ClosedLidMode) async {
        guard status != .arming, status != .restoring else { return }
        if activeMode != nil { await stop() }
        if mode == .standard, selectorCapability?.isAvailable != true { await probeCapability() }
        status = .arming
        switch mode {
        case .standard:
            guard selectorCapability?.isAvailable == true else {
                status = .unavailable
                return
            }
            do {
                lastStandardEvidence = try await standardSession.arm()
                activeMode = .standard
                status = .activeStandard
                await startSafetyMonitor(mode: .standard)
            } catch {
                _ = standardSession.directRestore()
                activeMode = nil
                status = .failed(Self.message(for: error))
            }
        case .powerProtect:
            do {
                try await powerProtect.enableVerified()
                guard powerProtect.state == .ready(sleepDisabled: true) else {
                    throw PowerHelperError.verificationFailed
                }
                activeMode = .powerProtect
                status = .activePowerProtect
                await startSafetyMonitor(mode: .powerProtect)
            } catch {
                try? await powerProtect.restore()
                activeMode = nil
                status = .failed(error.localizedDescription)
            }
        }
    }

    func stop() async {
        await safetyMonitor?.stop()
        guard let mode = activeMode else {
            status = .off
            return
        }
        status = .restoring
        switch mode {
        case .standard:
            do {
                try await standardSession.disarm()
                activeMode = nil
                lastStandardEvidence = nil
                status = .off
            } catch {
                let result = standardSession.directRestore()
                lastStandardEvidence = nil
                if result == KERN_SUCCESS {
                    activeMode = nil
                    status = .off
                } else {
                    activeMode = .standard
                    status = .failed("Normal sleep could not be restored")
                }
            }
        case .powerProtect:
            do {
                try await powerProtect.restore()
                guard powerProtect.state == .ready(sleepDisabled: false) else {
                    throw PowerHelperError.verificationFailed
                }
                activeMode = nil
                status = .off
            } catch {
                activeMode = .powerProtect
                status = .failed(error.localizedDescription)
            }
        }
    }

    func safetyStop(reason: ClosedLidSafetyStopReason) async {
        await stop()
        if status == .off {
            status = .safetyStopped(reason)
            return
        }
        if case let .failed(message) = status {
            status = .failed("\(Self.safetyMessage(reason)): \(message)")
        }
    }

    func refresh() async {
        switch activeMode {
        case .standard:
            do {
                let response = try await standardSession.status()
                guard response.state == .armed, response.selectorResult == KERN_SUCCESS else {
                    await safetyStop(reason: .heartbeatLost)
                    return
                }
                lastStandardEvidence = response.evidence
                status = .activeStandard
            } catch {
                _ = standardSession.directRestore()
                activeMode = nil
                await safetyMonitor?.stop()
                status = .safetyStopped(.heartbeatLost)
            }
        case .powerProtect:
            await powerProtect.refresh()
            if powerProtect.state == .ready(sleepDisabled: true) {
                status = .activePowerProtect
            } else {
                await safetyStop(reason: .heartbeatLost)
            }
        case nil:
            return
        }
    }

    func standardSessionEvidence() async -> ClosedLidStandardSessionEvidence? {
        await refresh()
        return lastStandardEvidence
    }

    func shutdownForTermination() async -> Bool {
        guard requiresTerminationDrain else { return true }
        await stop()
        return status == .off || {
            if case .safetyStopped = status { return true }
            return false
        }()
    }

    func restoreImmediatelyForTermination() {
        if activeMode == .standard { _ = standardSession.directRestore() }
        if activeMode == .powerProtect {
            Task { [powerProtect] in try? await powerProtect.restore() }
        }
        Task { [safetyMonitor] in await safetyMonitor?.stop() }
        activeMode = nil
        lastStandardEvidence = nil
        status = .off
    }

    func updateSettings(_ newSettings: ClosedLidSafetySettings) {
        settings = ClosedLidSafetySettings(
            durationMinutes: newSettings.durationMinutes,
            batteryFloorPercent: newSettings.batteryFloorPercent,
            onlyWhileCharging: newSettings.onlyWhileCharging,
            stopOnLowPowerMode: newSettings.stopOnLowPowerMode,
            stopOnThermalPressure: newSettings.stopOnThermalPressure
        )
    }

    func recordStandardPhysicalTest(success: Bool) {
        let key = Keys.attestationPrefix + hardwareIdentity().attestationKey
        if success, selectorCapability?.isAvailable == true {
            defaults.set(true, forKey: key)
            standardCompatibility = .verified
        } else {
            defaults.removeObject(forKey: key)
            standardCompatibility = selectorCapability?.isAvailable == true ? .needsVerification : .unavailable
        }
    }

    private var hasCurrentAttestation: Bool {
        defaults.bool(forKey: Keys.attestationPrefix + hardwareIdentity().attestationKey)
    }

    private func startSafetyMonitor(mode: ClosedLidMode) async {
        guard let safetyMonitor else { return }
        let configuredSettings = settings
        await safetyMonitor.start(
            settings: configuredSettings,
            snapshot: { try IOKitClosedLidPowerSnapshotProvider().snapshot() },
            heartbeat: { [weak self] in
                guard let self else { throw CancellationError() }
                switch mode {
                case .standard:
                    try await self.standardHeartbeat()
                case .powerProtect:
                    try await self.powerProtectHeartbeat()
                }
            },
            onStop: { [weak self] reason in
                guard let self else { return }
                await self.safetyStop(reason: reason)
            }
        )
    }

    private func standardHeartbeat() async throws {
        lastStandardEvidence = try await standardSession.heartbeat()
    }

    private func powerProtectHeartbeat() async throws {
        guard await powerProtect.heartbeat() else { throw PowerHelperError.verificationFailed }
    }

    private static func safetyMessage(_ reason: ClosedLidSafetyStopReason) -> String {
        switch reason {
        case .durationExpired: "Duration safety limit reached"
        case .batteryBelowFloor: "Battery safety floor reached"
        case .externalPowerDisconnected: "External power disconnected"
        case .lowPowerModeEnabled: "Low Power Mode enabled"
        case .thermalPressure: "Thermal pressure safety limit reached"
        case .heartbeatLost: "Fail-safe heartbeat lost"
        case .monitorFailure: "Safety state could not be verified"
        }
    }

    private func handleUnexpectedGuardExit() async {
        guard activeMode == .standard else { return }
        _ = standardSession.directRestore()
        activeMode = nil
        await safetyMonitor?.stop()
        lastStandardEvidence = nil
        status = .safetyStopped(.heartbeatLost)
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Keys.safetySettings)
        }
    }

    private static func message(for error: Error) -> String {
        if let guardError = error as? ClosedLidStandardGuardError {
            switch guardError {
            case .unavailable: return "Closed-lid guard is unavailable"
            case .invalidResponse: return "Closed-lid guard returned an invalid response"
            case let .selectorFailure(result): return "Closed-lid selector failed (\(result))"
            }
        }
        return "Closed-lid session could not be started"
    }
}

enum ClosedLidSystemIdentity {
    static func current() -> ClosedLidHardwareIdentity {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return ClosedLidHardwareIdentity(
            model: sysctlString("hw.model") ?? "unknown",
            osMajor: version.majorVersion,
            osMinor: version.minorVersion,
            osBuild: sysctlString("kern.osversion") ?? "unknown"
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1, size <= 4096 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        let bytes = value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8)
    }
}
