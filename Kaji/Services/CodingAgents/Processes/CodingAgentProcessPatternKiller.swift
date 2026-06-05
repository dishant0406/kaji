import Foundation

enum CodingAgentProcessPatternKiller {
    enum Signal {
        case terminate
        case kill

        var argument: String {
            switch self {
            case .terminate: "-TERM"
            case .kill: "-KILL"
            }
        }
    }

    static func kill(patterns: [String], signal: Signal) async -> [String] {
        await Task.detached(priority: .utility) {
            patterns.compactMap { pattern in
                do {
                    try run(pattern: pattern, signal: signal)
                    return nil
                } catch {
                    return "\(pattern): \(error.localizedDescription)"
                }
            }
        }.value
    }

    static func arguments(pattern: String, signal: Signal) -> [String] {
        [signal.argument, "-f", pattern]
    }

    private static func run(pattern: String, signal: Signal) throws {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = arguments(pattern: trimmed, signal: signal)
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        try process.run()
        let timedOut = finished.wait(timeout: .now() + 5) == .timedOut
        if timedOut {
            process.terminate()
            process.waitUntilExit()
        }

        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            throw CodingAgentProcessKillError.signalFailed(process.terminationStatus)
        }
    }
}
