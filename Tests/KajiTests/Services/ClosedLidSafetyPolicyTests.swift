import ClosedLidCore
import Foundation
import Testing

@testable import Kaji

struct ClosedLidSafetyPolicyTests {
    private let safeSnapshot = ClosedLidPowerSnapshot(
        batteryPercent: 80,
        externalPowerConnected: true,
        lowPowerModeEnabled: false,
        thermalPressure: .nominal
    )

    @Test
    func eachEnabledSafetyBoundaryStopsWithItsSpecificReason() {
        let settings = ClosedLidSafetySettings(
            durationMinutes: 60,
            batteryFloorPercent: 20,
            onlyWhileCharging: true,
            stopOnLowPowerMode: true,
            stopOnThermalPressure: true
        )

        #expect(reason(settings, safeSnapshot, elapsed: .seconds(3_600)) == .durationExpired)
        #expect(reason(settings, snapshot(battery: 20)) == .batteryBelowFloor)
        #expect(reason(settings, snapshot(onPower: false)) == .externalPowerDisconnected)
        #expect(reason(settings, snapshot(lowPower: true)) == .lowPowerModeEnabled)
        #expect(reason(settings, snapshot(thermal: .serious)) == .thermalPressure)
        #expect(reason(settings, safeSnapshot, heartbeatAge: .seconds(15)) == .heartbeatLost)
    }

    @Test
    func disabledOptionalCutoffsDoNotStopASafeSession() {
        let settings = ClosedLidSafetySettings(
            durationMinutes: 60,
            batteryFloorPercent: 20,
            onlyWhileCharging: false,
            stopOnLowPowerMode: false,
            stopOnThermalPressure: false
        )
        let snapshot = ClosedLidPowerSnapshot(
            batteryPercent: 21,
            externalPowerConnected: false,
            lowPowerModeEnabled: true,
            thermalPressure: .critical
        )

        #expect(reason(settings, snapshot) == nil)
    }

    @Test
    func missingRequiredPowerReadingsFailClosed() {
        let batteryMissing = ClosedLidPowerSnapshot(
            batteryPercent: nil,
            externalPowerConnected: true,
            lowPowerModeEnabled: false,
            thermalPressure: .nominal
        )
        let powerMissing = ClosedLidPowerSnapshot(
            batteryPercent: 80,
            externalPowerConnected: nil,
            lowPowerModeEnabled: false,
            thermalPressure: .nominal
        )

        #expect(reason(ClosedLidSafetySettings(), batteryMissing) == .monitorFailure)
        #expect(reason(ClosedLidSafetySettings(onlyWhileCharging: true), powerMissing) == .monitorFailure)
    }

    @Test
    func persistedSettingsConstructorClampsUnsafeBounds() {
        let settings = ClosedLidSafetySettings(durationMinutes: -4, batteryFloorPercent: 900)

        #expect(settings.durationMinutes == 1)
        #expect(settings.batteryFloorPercent == 50)
    }

    private func reason(
        _ settings: ClosedLidSafetySettings,
        _ snapshot: ClosedLidPowerSnapshot,
        elapsed: Duration = .seconds(1),
        heartbeatAge: Duration = .seconds(1)
    ) -> ClosedLidSafetyStopReason? {
        ClosedLidSafetyPolicy.stopReason(
            settings: settings,
            snapshot: snapshot,
            elapsed: elapsed,
            heartbeatAge: heartbeatAge,
            heartbeatTimeout: .seconds(15)
        )
    }

    private func snapshot(
        battery: Int = 80,
        onPower: Bool = true,
        lowPower: Bool = false,
        thermal: ClosedLidPowerSnapshot.ThermalPressure = .nominal
    ) -> ClosedLidPowerSnapshot {
        .init(
            batteryPercent: battery,
            externalPowerConnected: onPower,
            lowPowerModeEnabled: lowPower,
            thermalPressure: thermal
        )
    }
}
