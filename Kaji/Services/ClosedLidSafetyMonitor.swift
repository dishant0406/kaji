import ClosedLidCore
import Foundation
import IOKit.ps

struct ClosedLidPowerSnapshot: Equatable {
    enum ThermalPressure: Equatable {
        case nominal
        case fair
        case serious
        case critical
    }

    let batteryPercent: Int?
    let externalPowerConnected: Bool?
    let lowPowerModeEnabled: Bool
    let thermalPressure: ThermalPressure
}

enum ClosedLidPowerSnapshotError: Error, Equatable {
    case powerSourcesUnavailable
    case batteryStateUnavailable
}

struct IOKitClosedLidPowerSnapshotProvider {
    func snapshot() throws -> ClosedLidPowerSnapshot {
        guard let information = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(information)?.takeRetainedValue() as? [CFTypeRef]
        else { throw ClosedLidPowerSnapshotError.powerSourcesUnavailable }

        var batteryPercent: Int?
        var externalPowerConnected: Bool?
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(information, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = description[kIOPSTypeKey as String] as? String
            guard type == kIOPSInternalBatteryType as String else { continue }
            let current = description[kIOPSCurrentCapacityKey as String] as? Int
            let maximum = description[kIOPSMaxCapacityKey as String] as? Int
            if let current, let maximum, maximum > 0 {
                batteryPercent = min(max(Int((Double(current) / Double(maximum) * 100).rounded()), 0), 100)
            }
            if let state = description[kIOPSPowerSourceStateKey as String] as? String {
                externalPowerConnected = state == kIOPSACPowerValue as String
            }
            break
        }
        guard batteryPercent != nil, externalPowerConnected != nil else {
            throw ClosedLidPowerSnapshotError.batteryStateUnavailable
        }
        return ClosedLidPowerSnapshot(
            batteryPercent: batteryPercent,
            externalPowerConnected: externalPowerConnected,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalPressure: Self.thermalPressure(ProcessInfo.processInfo.thermalState)
        )
    }

    private static func thermalPressure(_ state: ProcessInfo.ThermalState) -> ClosedLidPowerSnapshot.ThermalPressure {
        switch state {
        case .nominal:
            .nominal
        case .fair:
            .fair
        case .serious:
            .serious
        case .critical:
            .critical
        @unknown default:
            .critical
        }
    }
}

enum ClosedLidSafetyPolicy {
    static func stopReason(
        settings: ClosedLidSafetySettings,
        snapshot: ClosedLidPowerSnapshot,
        elapsed: Duration,
        heartbeatAge: Duration,
        heartbeatTimeout: Duration
    ) -> ClosedLidSafetyStopReason? {
        if elapsed >= .seconds(settings.durationMinutes * 60) {
            return .durationExpired
        }
        guard let batteryPercent = snapshot.batteryPercent else {
            return .monitorFailure
        }
        if batteryPercent <= settings.batteryFloorPercent {
            return .batteryBelowFloor
        }
        if settings.onlyWhileCharging {
            guard let externalPowerConnected = snapshot.externalPowerConnected else {
                return .monitorFailure
            }
            if !externalPowerConnected {
                return .externalPowerDisconnected
            }
        }
        if settings.stopOnLowPowerMode, snapshot.lowPowerModeEnabled {
            return .lowPowerModeEnabled
        }
        if settings.stopOnThermalPressure,
           snapshot.thermalPressure == .serious || snapshot.thermalPressure == .critical
        {
            return .thermalPressure
        }
        if heartbeatAge >= heartbeatTimeout {
            return .heartbeatLost
        }
        return nil
    }
}

actor ClosedLidSafetyMonitor {
    typealias Snapshot = @Sendable () async throws -> ClosedLidPowerSnapshot
    typealias Heartbeat = @Sendable () async throws -> Void
    typealias StopHandler = @Sendable (ClosedLidSafetyStopReason) async -> Void

    private let clock = ContinuousClock()
    private let cadence: Duration
    private let heartbeatTimeout: Duration
    private var monitoringTask: Task<Void, Never>?
    private var settings = ClosedLidSafetySettings()
    private var startedAt: ContinuousClock.Instant?
    private var lastHeartbeatAt: ContinuousClock.Instant?

    init(cadence: Duration = .seconds(2), heartbeatTimeout: Duration = .seconds(15)) {
        self.cadence = cadence
        self.heartbeatTimeout = heartbeatTimeout
    }

    func start(
        settings: ClosedLidSafetySettings,
        snapshot: @escaping Snapshot,
        heartbeat: @escaping Heartbeat,
        onStop: @escaping StopHandler
    ) {
        stop()
        self.settings = settings
        let now = clock.now
        startedAt = now
        lastHeartbeatAt = now
        monitoringTask = Task { [weak self] in
            guard let self else { return }
            await self.run(snapshot: snapshot, heartbeat: heartbeat, onStop: onStop)
        }
    }

    func update(settings: ClosedLidSafetySettings) {
        self.settings = settings
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        startedAt = nil
        lastHeartbeatAt = nil
    }

    private func run(
        snapshot: @escaping Snapshot,
        heartbeat: @escaping Heartbeat,
        onStop: @escaping StopHandler
    ) async {
        while !Task.isCancelled {
            do {
                try await heartbeat()
                lastHeartbeatAt = clock.now
            } catch {
                await stopOnce(reason: .heartbeatLost, handler: onStop)
                return
            }
            let powerSnapshot: ClosedLidPowerSnapshot
            do {
                powerSnapshot = try await snapshot()
            } catch {
                await stopOnce(reason: .monitorFailure, handler: onStop)
                return
            }
            let now = clock.now
            guard let startedAt, let lastHeartbeatAt else {
                await stopOnce(reason: .monitorFailure, handler: onStop)
                return
            }
            if let reason = ClosedLidSafetyPolicy.stopReason(
                settings: settings,
                snapshot: powerSnapshot,
                elapsed: startedAt.duration(to: now),
                heartbeatAge: lastHeartbeatAt.duration(to: now),
                heartbeatTimeout: heartbeatTimeout
            ) {
                await stopOnce(reason: reason, handler: onStop)
                return
            }
            do {
                try await clock.sleep(for: cadence)
            } catch {
                return
            }
        }
    }

    private func stopOnce(reason: ClosedLidSafetyStopReason, handler: StopHandler) async {
        monitoringTask = nil
        startedAt = nil
        lastHeartbeatAt = nil
        await handler(reason)
    }
}
