import Foundation

enum AgentVerificationRunner {
    struct Plan: Equatable {
        let command: String
        let workingDirectory: String
    }

    static func plan(for run: AgentRun, project: Project? = nil, fileManager: FileManager = .default) -> Plan? {
        guard let worktreePath = run.worktreePath else { return nil }
        if let command = project?.verificationCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty {
            return Plan(command: command, workingDirectory: worktreePath)
        }
        let packagePath = (worktreePath as NSString).appendingPathComponent("Package.swift")
        guard fileManager.fileExists(atPath: packagePath) else { return nil }
        return Plan(command: "swift build && swift test", workingDirectory: worktreePath)
    }

    @MainActor
    static func verify(runID: UUID, project: Project? = nil, store: AgentRunStore = .shared) {
        guard let run = store.run(id: runID), let plan = plan(for: run, project: project) else {
            store.finishVerification(runID: runID, status: .unavailable, output: "No verification command is available.")
            return
        }
        store.startVerification(runID: runID, command: plan.command)
        Task {
            let result = await execute(plan: plan)
            await MainActor.run {
                store.finishVerification(
                    runID: runID,
                    status: result.status == 0 ? .passed : .failed,
                    output: result.output
                )
            }
        }
    }

    private static func execute(plan: Plan) async -> VerificationResult {
        await GitProcessRunner.offMain {
            runSync(plan: plan)
        }
    }

    private static func runSync(plan: Plan) -> VerificationResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", plan.command]
        process.currentDirectoryURL = URL(fileURLWithPath: plan.workingDirectory)

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return VerificationResult(status: 1, output: error.localizedDescription)
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return VerificationResult(status: process.terminationStatus, output: trimmed(output))
    }

    private static func trimmed(_ output: String) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).suffix(30)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct VerificationResult {
        let status: Int32
        let output: String
    }
}
