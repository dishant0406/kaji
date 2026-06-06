import Foundation

struct KajiCodeGraphNodeQuery {
    let id: String?
    let label: String?
    let path: String?
}

struct KajiCodeGraphSearchResult {
    let document: KajiCodeGraphDocument
    let nodes: [KajiCodeGraphNode]

    var text: String {
        guard !nodes.isEmpty else { return "No graph nodes found." }
        let body = nodes.enumerated().map { index, node in
            let file = node.sourceFile.map { " file=\($0)" } ?? ""
            let community = node.community.map { " community=\($0)" } ?? ""
            return "\(index + 1). \(node.label) id=\(node.id) type=\(node.fileType) degree=\(node.degree)\(community)\(file)"
        }.joined(separator: "\n")
        return "Found \(nodes.count) graph nodes from \(document.nodes.count) total nodes:\n\(body)"
    }

    var details: KajiAgentJSONValue {
        .object([
            "projectPath": .string(document.projectPath),
            "builtAt": .string(document.builtAt),
            "nodes": .array(nodes.map(\.agentJSON)),
        ])
    }
}

struct KajiCodeGraphNeighborResult {
    let document: KajiCodeGraphDocument
    let node: KajiCodeGraphNode
    let edges: [KajiCodeGraphNeighborEdge]

    var text: String {
        guard !edges.isEmpty else { return "No graph neighbors found for \(node.label) (\(node.id))." }
        let body = edges.enumerated().map { index, neighbor in
            let other = "\(neighbor.otherLabel(for: node.id)) [\(neighbor.otherID(for: node.id))]"
            return "\(index + 1). \(neighbor.direction(for: node.id)) \(neighbor.edge.relation) \(other)"
        }.joined(separator: "\n")
        return "Found \(edges.count) graph edges for \(node.label) (\(node.id)):\n\(body)"
    }

    var details: KajiAgentJSONValue {
        .object([
            "projectPath": .string(document.projectPath),
            "builtAt": .string(document.builtAt),
            "node": node.agentJSON,
            "edges": .array(edges.map(\.agentJSON)),
        ])
    }
}

struct KajiCodeGraphNeighborEdge {
    let edge: KajiCodeGraphEdge
    let source: KajiCodeGraphNode?
    let target: KajiCodeGraphNode?

    func direction(for nodeID: String) -> String {
        edge.source == nodeID ? "outgoing" : "incoming"
    }

    func otherID(for nodeID: String) -> String {
        edge.source == nodeID ? edge.target : edge.source
    }

    func otherLabel(for nodeID: String) -> String {
        edge.source == nodeID ? target?.label ?? edge.target : source?.label ?? edge.source
    }

    var agentJSON: KajiAgentJSONValue {
        .object([
            "source": .string(edge.source),
            "target": .string(edge.target),
            "relation": .string(edge.relation),
            "confidence": .string(edge.confidence),
            "sourceLabel": source.map { .string($0.label) } ?? .null,
            "targetLabel": target.map { .string($0.label) } ?? .null,
        ])
    }
}

struct KajiCodeGraphPathResult {
    let document: KajiCodeGraphDocument
    let source: KajiCodeGraphNode
    let target: KajiCodeGraphNode
    let steps: [KajiCodeGraphPathStep]?

    var text: String {
        guard let steps else { return "No graph path found from \(source.label) to \(target.label) within the requested depth." }
        guard !steps.isEmpty else { return "Source and target resolve to the same graph node: \(source.label) (\(source.id))." }
        let body = steps.enumerated().map { index, step in
            "\(index + 1). \(step.direction) \(step.edge.relation) \(step.node.label) [\(step.node.id)]"
        }.joined(separator: "\n")
        return "Found graph path from \(source.label) to \(target.label):\n\(body)"
    }

    var details: KajiAgentJSONValue {
        .object([
            "projectPath": .string(document.projectPath),
            "builtAt": .string(document.builtAt),
            "source": source.agentJSON,
            "target": target.agentJSON,
            "steps": steps.map { .array($0.map(\.agentJSON)) } ?? .null,
        ])
    }
}

struct KajiCodeGraphPathStep {
    let edge: KajiCodeGraphEdge
    let node: KajiCodeGraphNode
    let direction: String

    var agentJSON: KajiAgentJSONValue {
        .object(["direction": .string(direction), "relation": .string(edge.relation), "node": node.agentJSON])
    }
}

struct KajiCodeGraphHotspotResult {
    let document: KajiCodeGraphDocument
    let nodes: [KajiCodeGraphNode]

    var text: String {
        guard !nodes.isEmpty else { return "No graph hotspots found." }
        let body = nodes.enumerated().map { index, node in
            let file = node.sourceFile.map { " file=\($0)" } ?? ""
            return "\(index + 1). \(node.label) id=\(node.id) degree=\(node.degree)\(file)"
        }.joined(separator: "\n")
        return "Top \(nodes.count) graph hotspots:\n\(body)"
    }

    var details: KajiAgentJSONValue {
        .object([
            "projectPath": .string(document.projectPath),
            "builtAt": .string(document.builtAt),
            "nodes": .array(nodes.map(\.agentJSON)),
        ])
    }
}

extension KajiCodeGraphNode {
    var agentJSON: KajiAgentJSONValue {
        .object([
            "id": .string(id),
            "label": .string(label),
            "fileType": .string(fileType),
            "sourceFile": sourceFile.map { .string($0) } ?? .null,
            "community": community.map { .number(Double($0)) } ?? .null,
            "degree": .number(Double(degree)),
        ])
    }
}
