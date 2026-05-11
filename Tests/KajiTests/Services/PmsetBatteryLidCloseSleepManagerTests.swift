import Foundation
import Testing

@testable import Kaji

@MainActor
struct PmsetBatteryLidCloseSleepManagerTests {
    @Test
    func beginRunsBatteryDisableSleepCommand() {
        let runner = RecordingAdminPowerCommandRunner()
        let manager = PmsetBatteryLidCloseSleepManager(
            commandRunner: runner,
            isExecutableFile: { _ in true }
        )

        let status = manager.begin()

        #expect(status == .active)
        #expect(runner.arguments == [["-b", "disablesleep", "1"]])
    }

    @Test
    func endRunsBatteryRestoreSleepCommand() {
        let runner = RecordingAdminPowerCommandRunner()
        let manager = PmsetBatteryLidCloseSleepManager(
            commandRunner: runner,
            isExecutableFile: { _ in true }
        )

        _ = manager.begin()
        let status = manager.end()

        #expect(status == .inactive)
        #expect(runner.arguments == [
            ["-b", "disablesleep", "1"],
            ["-b", "disablesleep", "0"],
        ])
    }

    @Test
    func unavailableWhenRequiredToolsAreMissing() {
        let runner = RecordingAdminPowerCommandRunner()
        let manager = PmsetBatteryLidCloseSleepManager(
            commandRunner: runner,
            isExecutableFile: { $0 != "/usr/bin/osascript" }
        )

        let status = manager.begin()

        #expect(status == .unavailable)
        #expect(runner.arguments.isEmpty)
    }
}

@MainActor
private final class RecordingAdminPowerCommandRunner: AdminPowerCommandRunning {
    private(set) var arguments: [[String]] = []
    var result = true

    func runPmset(arguments: [String]) -> Bool {
        self.arguments.append(arguments)
        return result
    }
}
