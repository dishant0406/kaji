import Foundation
import Testing

@testable import Droid

@MainActor
@Suite("DroidCodeGraphFinalizer", .serialized)
struct DroidCodeGraphFinalizerTests {
    @Test
    func finalizesReadyAgentOutputWithBundledAdapter() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? fileManager.removeItem(at: root)
        }

        let projectID = UUID()
        let worktreeID = UUID()
        let output = root
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(worktreeID.uuidString, isDirectory: true)
            .appendingPathComponent("graphify-out", isDirectory: true)
        let work = output.appendingPathComponent("agent-work", isDirectory: true)
        let graphifyOutput = work.appendingPathComponent("graphify-out", isDirectory: true)
        let python = root.appendingPathComponent(".venv/bin/python")
        let adapter = root.appendingPathComponent("adapter/droidcodegraph_runner.py")
        try fileManager.createDirectory(at: graphifyOutput, withIntermediateDirectories: true)
        try Data("{\"nodes\":[],\"links\":[]}".utf8).write(to: graphifyOutput.appendingPathComponent("graph.json"))
        try Data("# Graph\n".utf8).write(to: graphifyOutput.appendingPathComponent("GRAPH_REPORT.md"))

        let request = DroidCodeGraphRunRequest(
            projectID: projectID,
            worktreeID: worktreeID,
            projectPath: "/tmp/project",
            mode: "build"
        )
        let runner = RecordingDroidCodeGraphRunner(output: output, buildID: "build-1")
        let status = try await DroidCodeGraphFinalizer(
            runner: runner,
            python: python,
            adapterScript: adapter,
            installAdapter: {
                try fileManager.createDirectory(at: adapter.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("adapter".utf8).write(to: adapter)
            }
        ).finalizeIfReady(
            request: request,
            output: output,
            work: work,
            buildID: "build-1"
        )
        let call = await runner.calls.first

        #expect(status?.ok == true)
        #expect(call?.arguments.contains("finalize") == true)
        #expect(call?.executable == python.path)
        #expect(call?.arguments.first == adapter.path)
        #expect(fileManager.fileExists(atPath: adapter.path))
    }
}

private actor RecordingDroidCodeGraphRunner: DroidCodeGraphProcessRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    let output: URL
    let buildID: String
    var calls: [Call] = []

    init(output: URL, buildID: String) {
        self.output = output
        self.buildID = buildID
    }

    func run(
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]
    ) async throws -> DroidCodeGraphProcessResult {
        calls.append(Call(executable: executable, arguments: arguments))
        let status = DroidCodeGraphStatus(
            ok: true,
            mode: "build",
            nodes: 0,
            edges: 0,
            communities: 0,
            graphPath: output.appendingPathComponent("graph.json").path,
            droidGraphPath: output.appendingPathComponent("droid-graph.json").path,
            reportPath: output.appendingPathComponent("GRAPH_REPORT.md").path,
            buildID: buildID,
            state: "complete",
            message: nil
        )
        let data = try JSONEncoder().encode(status)
        try data.write(to: output.appendingPathComponent("status.json"))
        return DroidCodeGraphProcessResult(status: 0, stdout: "", stderr: "")
    }
}
