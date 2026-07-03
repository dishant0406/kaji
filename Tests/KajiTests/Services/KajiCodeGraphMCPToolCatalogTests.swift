import Foundation
import Testing

@testable import Kaji

struct KajiCodeGraphMCPToolCatalogTests {
    @Test
    func exposesReadOnlyCodeGraphToolsWithoutGraph() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = root.appendingPathComponent("Kaji/Resources/CodingAgents/CodeGraph/kaji-codegraph/codegraph-main.js")
        guard FileManager.default.fileExists(atPath: script.path) else { return }

        let output = try runNode("""
        const { dispatch } = require('\(script.path)');
        const tools = dispatch('tools/list', {}).tools.map(tool => tool.name);
        console.log(JSON.stringify(tools));
        """)
        let data = try #require(output.data(using: .utf8))
        let tools = try #require(JSONSerialization.jsonObject(with: data) as? [String])

        #expect(tools.contains("code_graph_status"))
        #expect(tools.contains("code_graph_projects"))
        #expect(tools.contains("code_graph_search"))
        #expect(tools.contains("code_graph_neighbors"))
        #expect(tools.contains("code_graph_path"))
        #expect(tools.contains("code_graph_hotspots"))
    }

    @Test
    func missingGraphReturnsStructuredStatus() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = root.appendingPathComponent("Kaji/Resources/CodingAgents/CodeGraph/kaji-codegraph/codegraph-main.js")
        guard FileManager.default.fileExists(atPath: script.path) else { return }

        let output = try runNode("""
        process.env.HOME = '/tmp/kaji-codegraph-empty-home';
        process.env.KAJI_CODE_GRAPH_ROOT_DIR = '/tmp/kaji-codegraph-empty-home/extensions/kajicodegraph';
        const { dispatch } = require('\(script.path)');
        const result = dispatch('tools/call', { name: 'code_graph_status', arguments: { project_path: '/tmp/nope' } });
        console.log(JSON.stringify(result));
        """)
        let data = try #require(output.data(using: .utf8))
        let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)

        #expect(text.contains(#""ready": false"#))
        #expect(text.contains(#""projects": []"#))
    }

    @Test
    func readyGraphCanBeSelectedAndSearched() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = root.appendingPathComponent("Kaji/Resources/CodingAgents/CodeGraph/kaji-codegraph/codegraph-main.js")
        guard FileManager.default.fileExists(atPath: script.path) else { return }

        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.writeGraph()

        let output = try runNode("""
        process.env.KAJI_CODE_GRAPH_ROOT_DIR = '\(fixture.root.path)';
        const { dispatch } = require('\(script.path)');
        const status = dispatch('tools/call', { name: 'code_graph_status', arguments: { project_path: '\(fixture.project.path)' } });
        const search = dispatch('tools/call', { name: 'code_graph_search', arguments: { project_path: '\(fixture.project.path)', query: 'Shim', limit: 2 } });
        console.log(JSON.stringify({ status, search }));
        """)
        let data = try #require(output.data(using: .utf8))
        let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let status = try toolText(result, key: "status")
        let search = try toolText(result, key: "search")

        #expect(status.contains(#""ready": true"#))
        #expect(search.contains("ShimNode"))
    }

    private func toolText(_ result: [String: Any], key: String) throws -> String {
        let toolResult = try #require(result[key] as? [String: Any])
        let content = try #require(toolResult["content"] as? [[String: Any]])
        return try #require(content.first?["text"] as? String)
    }

    private func runNode(_ code: String) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "-e", code]
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            throw NodeError(String(decoding: errorData, as: UTF8.self))
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class Fixture {
    let fileManager = FileManager.default
    let root: URL
    let project: URL

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        project = root.appendingPathComponent("worktree", isDirectory: true)
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }

    func writeGraph() throws {
        let output = root.appendingPathComponent("projects/project/worktree/graphify-out", isDirectory: true)
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        try Data(graphJSON.utf8).write(to: output.appendingPathComponent("kaji-graph.json"))
        try Data("# Graph Report\n".utf8).write(to: output.appendingPathComponent("GRAPH_REPORT.md"))
    }

    private var graphJSON: String {
        """
        {
          "projectPath": "\(project.path)",
          "builtAt": "2026-07-03T00:00:00Z",
          "nodes": [
            { "id": "shim", "label": "ShimNode", "source_file": "Shim.swift", "file_type": "swift", "degree": 1 }
          ],
          "edges": [],
          "communities": []
        }
        """
    }
}

private struct NodeError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
