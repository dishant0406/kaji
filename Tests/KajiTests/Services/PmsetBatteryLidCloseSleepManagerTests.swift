import Foundation
import Testing

@testable import Kaji

@MainActor
struct PmsetBatteryLidCloseSleepManagerTests {
    @Test
    func beginRunsBatteryDisableSleepCommand() async {
        let runner = RecordingAdminPowerCommandRunner()
        let manager = PmsetBatteryLidCloseSleepManager(
            commandRunner: runner,
            isExecutableFile: { _ in true }
        )

        let status = await manager.begin()

        #expect(status == .active)
        #expect(runner.arguments == [["-b", "disablesleep", "1"]])
    }

    @Test
    func endRunsBatteryRestoreSleepCommand() async {
        let runner = RecordingAdminPowerCommandRunner()
        let manager = PmsetBatteryLidCloseSleepManager(
            commandRunner: runner,
            isExecutableFile: { _ in true }
        )

        _ = await manager.begin()
        let status = await manager.end()

        #expect(status == .inactive)
        #expect(runner.arguments == [
            ["-b", "disablesleep", "1"],
            ["-b", "disablesleep", "0"],
        ])
    }

    @Test
    func unavailableWhenRequiredToolsAreMissing() async {
        let runner = RecordingAdminPowerCommandRunner()
        let manager = PmsetBatteryLidCloseSleepManager(
            commandRunner: runner,
            isExecutableFile: { $0 != "/usr/bin/osascript" }
        )

        let status = await manager.begin()

        #expect(status == .unavailable)
        #expect(runner.arguments.isEmpty)
    }
}

@MainActor
private final class RecordingAdminPowerCommandRunner: AdminPowerCommandRunning {
    private(set) var arguments: [[String]] = []
    var result = true

    func runPmset(arguments: [String]) async -> Bool {
        self.arguments.append(arguments)
        return result
    }
}
