import Foundation

@MainActor
protocol AdminPowerCommandRunning {
    func runPmset(arguments: [String]) async -> Bool
}

@MainActor
final class OsaScriptAdminPowerCommandRunner: AdminPowerCommandRunning {
    func runPmset(arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let command = (["/usr/bin/pmset"] + arguments).joined(separator: " ")
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = [
                    "-e",
                    "do shell script \"\(command)\" with administrator privileges",
                ]
                process.standardOutput = Pipe()
                process.standardError = Pipe()

                let finished = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in finished.signal() }

                do {
                    try process.run()
                    let timedOut = finished.wait(timeout: .now() + 10) == .timedOut
                    if timedOut {
                        process.terminate()
                        process.waitUntilExit()
                        continuation.resume(returning: false)
                        return
                    }
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
