import Foundation
import Testing

struct OpenCodePluginRuntimeTests {
    @Test
    func bundledPluginParsesWithBun() throws {
        let plugin = try pluginURL()
        let result = try run("bun", [plugin.path])

        #expect(result.status == 0)
        #expect(result.output.isEmpty)
    }

    @Test
    func idleStatusSendsSingleCompletionAfterStop() throws {
        let plugin = try pluginURL()
        let directory = tempDirectory()
        let capture = directory.appendingPathComponent("capture.tsv")
        let hook = directory.appendingPathComponent("hook.sh")
        try """
        #!/bin/sh
        printf '%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$5" >> "$KAJI_CAPTURE"
        """.write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)

        let runner = directory.appendingPathComponent("runner.mjs")
        try runnerScript(plugin: plugin).write(to: runner, atomically: true, encoding: .utf8)

        let result = try run("bun", [runner.path], environment: [
            "KAJI_CAPTURE": capture.path,
            "KAJI_HOOK_CLIENT_PATH": hook.path,
            "KAJI_PANE_ID": UUID().uuidString,
            "KAJI_PROJECT_ID": UUID().uuidString,
            "KAJI_WORKTREE_ID": UUID().uuidString,
            "KAJI_WORKTREE_PATH": "/tmp/muxy",
        ])
        let rows = try String(contentsOf: capture, encoding: .utf8)
            .split(separator: "\n")
            .map { $0.split(separator: "\t", maxSplits: 3).map(String.init) }
        let types = rows.compactMap(\.first)
        let activityTitles = rows.filter { $0.first == "opencode_activity" }.compactMap { $0.dropFirst(2).first }

        #expect(result.status == 0)
        #expect(types.filter { $0 == "opencode_activity" }.count == 2)
        #expect(activityTitles == ["start", "stop"])
        #expect(types.filter { $0 == "opencode" }.count == 1)
        #expect(types.filter { $0 == "opencode_session" }.count == 1)
        #expect(types.filter { $0 == "opencode_transcript" }.count == 1)
    }

    @Test
    func staleIdleDoesNotCompleteNewerSession() throws {
        let plugin = try pluginURL()
        let directory = tempDirectory()
        let capture = directory.appendingPathComponent("capture.tsv")
        let hook = try hookScript(in: directory)
        let runner = directory.appendingPathComponent("runner.mjs")
        try staleRunnerScript(plugin: plugin).write(to: runner, atomically: true, encoding: .utf8)

        let result = try run("bun", [runner.path], environment: [
            "KAJI_CAPTURE": capture.path,
            "KAJI_HOOK_CLIENT_PATH": hook.path,
            "KAJI_PANE_ID": UUID().uuidString,
        ])
        let rows = try String(contentsOf: capture, encoding: .utf8)
            .split(separator: "\n")
            .map { $0.split(separator: "\t", maxSplits: 3).map(String.init) }
        let types = rows.compactMap(\.first)
        let activityTitles = rows.filter { $0.first == "opencode_activity" }.compactMap { $0.dropFirst(2).first }

        #expect(result.status == 0)
        #expect(types.filter { $0 == "opencode" }.isEmpty)
        #expect(activityTitles == ["start"])
    }

    private func runnerScript(plugin: URL) -> String {
        """
        import { KajiNotificationPlugin } from "\(plugin.absoluteString)"

        const client = {
          session: {
            messages: async () => ({ data: [{ info: { role: "assistant" }, parts: [{ type: "text", text: "Final answer" }] }] }),
          },
        }
        const plugin = await KajiNotificationPlugin({ client })
        await plugin.event({ event: { type: "session.status", properties: { sessionID: "ses-1", status: "active" } } })
        await plugin.event({ event: { type: "session.status", properties: { sessionID: "ses-1", status: "idle" } } })
        await plugin.event({ event: { type: "session.idle", properties: { sessionID: "ses-1" } } })
        await plugin.event({ event: { type: "message.part.delta", properties: { sessionID: "ses-1" } } })
        """
    }

    private func staleRunnerScript(plugin: URL) -> String {
        """
        import { KajiNotificationPlugin } from "\(plugin.absoluteString)"

        const client = { session: { messages: async () => ({ data: [] }) } }
        const plugin = await KajiNotificationPlugin({ client })
        await plugin.event({ event: { type: "session.status", properties: { sessionID: "new-session", status: "active" } } })
        await plugin.event({ event: { type: "session.status", properties: { sessionID: "old-session", status: "idle" } } })
        """
    }

    private func hookScript(in directory: URL) throws -> URL {
        let hook = directory.appendingPathComponent("hook.sh")
        try """
        #!/bin/sh
        printf '%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$5" >> "$KAJI_CAPTURE"
        """.write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        return hook
    }

    private func pluginURL() throws -> URL {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Kaji/Resources/CodingAgents/OpenCode/opencode-kaji-plugin.js")
        try #require(FileManager.default.fileExists(atPath: url.path))
        return url
    }

    private func tempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func run(_ executable: String, _ arguments: [String], environment: [String: String] = [:]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.environment = processEnvironment(environment)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func processEnvironment(_ environment: [String: String]) -> [String: String] {
        var base = ProcessInfo.processInfo.environment
        let bunPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bun/bin").path
        let currentPath = base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        base["PATH"] = "\(bunPath):\(currentPath)"
        return base.merging(environment) { _, new in new }
    }
}
