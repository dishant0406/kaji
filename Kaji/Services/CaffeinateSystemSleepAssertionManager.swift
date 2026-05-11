import Foundation

@MainActor
final class CaffeinateSystemSleepAssertionManager: SystemSleepAssertionManaging {
    private var process: Process?
    private let pid: Int32
    private(set) var status: SystemSleepAssertionStatus = .inactive

    init(pid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.pid = pid
    }

    func begin() -> SystemSleepAssertionStatus {
        guard process == nil else { return status }

        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/caffeinate") else {
            status = .unavailable
            return status
        }

        let caffeinate = Process()
        caffeinate.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        caffeinate.arguments = ["-i", "-s", "-w", "\(pid)"]

        do {
            try caffeinate.run()
            process = caffeinate
            status = .active
        } catch {
            process = nil
            status = .failed
        }
        return status
    }

    func end() {
        guard let process else {
            status = .inactive
            return
        }
        process.terminate()
        self.process = nil
        status = .inactive
    }
}
