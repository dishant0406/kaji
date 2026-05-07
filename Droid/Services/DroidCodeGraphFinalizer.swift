import Foundation

@MainActor
struct DroidCodeGraphFinalizer {
    let runner: any DroidCodeGraphProcessRunning
    let fileManager: FileManager
    let python: URL
    let adapterScript: URL
    let installAdapter: () throws -> Void

    init(
        runner: any DroidCodeGraphProcessRunning = DroidCodeGraphProcessRunner(),
        fileManager: FileManager = .default,
        python: URL = DroidCodeGraphDirectory.python,
        adapterScript: URL = DroidCodeGraphDirectory.adapterScript,
        installAdapter: @escaping () throws -> Void = DroidCodeGraphInstaller.installBundledAdapter
    ) {
        self.runner = runner
        self.fileManager = fileManager
        self.python = python
        self.adapterScript = adapterScript
        self.installAdapter = installAdapter
    }

    func finalizeIfReady(
        request: DroidCodeGraphRunRequest,
        output: URL,
        work: URL,
        buildID: String
    ) async throws -> DroidCodeGraphStatus? {
        guard graphifyOutputIsReady(work: work) else { return nil }
        try installAdapter()
        let result = try await runner.run(
            executable: python.path,
            arguments: [
                adapterScript.path,
                "finalize",
                "--project",
                request.projectPath,
                "--out",
                output.path,
                "--work",
                work.path,
                "--mode",
                request.mode,
                "--build-id",
                buildID,
            ],
            workingDirectory: work.path,
            environment: [:]
        )
        guard result.status == 0 else {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw DroidCodeGraphInstallerError.commandFailed("DroidCodeGraph finalizer", result.status, detail)
        }
        return readFinalStatus(output: output, buildID: buildID)
    }

    func readFinalStatus(output: URL, buildID: String) -> DroidCodeGraphStatus? {
        let statusURL = output.appendingPathComponent("status.json")
        guard let data = try? Data(contentsOf: statusURL),
              let status = try? JSONDecoder().decode(DroidCodeGraphStatus.self, from: data),
              status.buildID == buildID,
              status.state != "running"
        else { return nil }
        return status
    }

    private func graphifyOutputIsReady(work: URL) -> Bool {
        let graph = work.appendingPathComponent("graphify-out/graph.json")
        let report = work.appendingPathComponent("graphify-out/GRAPH_REPORT.md")
        guard fileManager.fileExists(atPath: graph.path),
              fileManager.fileExists(atPath: report.path),
              let data = try? Data(contentsOf: graph),
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else { return false }
        return true
    }
}
