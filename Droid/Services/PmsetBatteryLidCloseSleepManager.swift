import Foundation

@MainActor
final class PmsetBatteryLidCloseSleepManager: BatteryLidCloseSleepManaging {
    private let commandRunner: AdminPowerCommandRunning
    private let isExecutableFile: (String) -> Bool
    private var didDisableSleep = false
    private(set) var status: SystemSleepAssertionStatus = .inactive

    init(
        commandRunner: AdminPowerCommandRunning = OsaScriptAdminPowerCommandRunner(),
        isExecutableFile: @escaping (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) {
        self.commandRunner = commandRunner
        self.isExecutableFile = isExecutableFile
    }

    func begin() -> SystemSleepAssertionStatus {
        guard status != .active else { return status }
        guard isExecutableFile("/usr/bin/pmset"), isExecutableFile("/usr/bin/osascript") else {
            status = .unavailable
            return status
        }
        guard commandRunner.runPmset(arguments: ["-b", "disablesleep", "1"]) else {
            status = .failed
            return status
        }
        didDisableSleep = true
        status = .active
        return status
    }

    func end() -> SystemSleepAssertionStatus {
        guard didDisableSleep else {
            status = .inactive
            return status
        }
        guard commandRunner.runPmset(arguments: ["-b", "disablesleep", "0"]) else {
            status = .failed
            return status
        }
        didDisableSleep = false
        status = .inactive
        return status
    }
}
