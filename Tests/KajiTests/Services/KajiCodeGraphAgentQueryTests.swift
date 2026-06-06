import Foundation
import Testing

@testable import Kaji

struct KajiCodeGraphAgentQueryTests {
    @Test
    func searchRanksLabelsAndIncludesDetails() throws {
        let graph = try writeGraph()
        defer { try? FileManager.default.removeItem(at: graph) }

        let result = try KajiCodeGraphAgentQuery.search(graphURL: graph, query: "Agent", limit: 2)

        #expect(Set(result.nodes.map(\.id)) == ["agent_runtime", "agent_store"])
        #expect(result.text.contains("Found 2 graph nodes"))
        #expect(result.details.objectValue?["nodes"]?.arrayValue?.count == 2)
    }

    @Test
    func neighborsResolvesByPathAndShowsDirections() throws {
        let graph = try writeGraph()
        defer { try? FileManager.default.removeItem(at: graph) }

        let optionalResult = try KajiCodeGraphAgentQuery.neighbors(
            graphURL: graph,
            id: nil,
            label: nil,
            path: "KajiAgentRuntime.swift",
            limit: 10
        )
        let result = try #require(optionalResult)

        #expect(result.node.id == "agent_runtime")
        #expect(result.text.contains("outgoing calls AgentStore"))
        #expect(result.text.contains("incoming owns AppState"))
        #expect(result.details.objectValue?["edges"]?.arrayValue?.count == 2)
    }


    @Test
    func pathFindsRelationshipBetweenNodes() throws {
        let graph = try writeGraph()
        defer { try? FileManager.default.removeItem(at: graph) }

        let optionalResult = try KajiCodeGraphAgentQuery.path(
            graphURL: graph,
            from: KajiCodeGraphNodeQuery(id: "app_state", label: nil, path: nil),
            to: KajiCodeGraphNodeQuery(id: nil, label: "AgentStore", path: nil),
            maxDepth: 3
        )
        let result = try #require(optionalResult)

        #expect(result.text.contains("Found graph path"))
        #expect(result.text.contains("KajiAgentRuntime"))
        #expect(result.details.objectValue?["steps"]?.arrayValue?.count == 2)
    }

    @Test
    func hotspotsSortsByDegree() throws {
        let graph = try writeGraph()
        defer { try? FileManager.default.removeItem(at: graph) }

        let result = try KajiCodeGraphAgentQuery.hotspots(graphURL: graph, limit: 2)

        #expect(result.nodes.map(\.id) == ["agent_runtime", "agent_store"])
        #expect(result.text.contains("Top 2 graph hotspots"))
    }

    @Test
    func reportTruncatesByLineLimit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try (1...30).map { "line \($0)" }.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let report = try KajiCodeGraphAgentQuery.report(url: url, maxLines: 20)

        #expect(report.contains("line 20"))
        #expect(!report.contains("line 21"))
        #expect(report.contains("truncated 10 lines"))
    }

    private func writeGraph() throws -> URL {
        let json = """
        {
          "projectPath": "/tmp/kaji",
          "builtAt": "2026-06-06T00:00:00Z",
          "nodes": [
            {"id": "app_state", "label": "AppState", "file_type": "swift", "source_file": "AppState.swift", "community": 1, "degree": 3},
            {"id": "agent_runtime", "label": "KajiAgentRuntime", "file_type": "swift", "source_file": "KajiAgentRuntime.swift", "community": 2, "degree": 9},
            {"id": "agent_store", "label": "AgentStore", "file_type": "swift", "source_file": "KajiAgentStore.swift", "community": 2, "degree": 6}
          ],
          "edges": [
            {"source": "agent_runtime", "target": "agent_store", "relation": "calls", "confidence": "EXTRACTED"},
            {"source": "app_state", "target": "agent_runtime", "relation": "owns", "confidence": "EXTRACTED"}
          ],
          "communities": [
            {"id": 1, "label": "App", "node_count": 1},
            {"id": 2, "label": "Agent", "node_count": 2}
          ]
        }
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
