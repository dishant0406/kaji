import Foundation

@MainActor
protocol AdminPowerCommandRunning {
    func runPmset(arguments: [String]) -> Bool
}

@MainActor
final class OsaScriptAdminPowerCommandRunner: AdminPowerCommandRunning {
    func runPmset(arguments: [String]) -> Bool {
        let process = Process()
        let command = (["/usr/bin/pmset"] + arguments).joined(separator: " ")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"\(command)\" with administrator privileges",
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
