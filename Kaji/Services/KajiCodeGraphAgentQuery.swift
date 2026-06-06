import Foundation

enum KajiCodeGraphAgentQuery {
    static func report(url: URL, maxLines: Int) throws -> String {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let clamped = min(max(maxLines, 20), 500)
        guard lines.count > clamped else { return text }
        return lines.prefix(clamped).joined(separator: "\n") + "\n\n... truncated \(lines.count - clamped) lines"
    }

    static func search(graphURL: URL, query: String, limit: Int) throws -> KajiCodeGraphSearchResult {
        let document = try KajiCodeGraphDocumentLoader.load(url: graphURL)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return KajiCodeGraphSearchResult(document: document, nodes: []) }
        let terms = trimmed.lowercased().split(separator: " ").map(String.init)
        let nodes = document.nodes
            .compactMap { node -> KajiCodeGraphRankedNode? in
                let score = score(node: node, terms: terms)
                guard score > 0 else { return nil }
                return KajiCodeGraphRankedNode(node: node, score: score)
            }
            .sorted(by: sortRankedNodes)
            .prefix(min(max(limit, 1), 80))
            .map(\.node)
        return KajiCodeGraphSearchResult(document: document, nodes: nodes)
    }

    static func neighbors(graphURL: URL, id: String?, label: String?, path: String?, limit: Int) throws -> KajiCodeGraphNeighborResult? {
        let document = try KajiCodeGraphDocumentLoader.load(url: graphURL)
        guard let node = resolveNode(document: document, id: id, label: label, path: path) else { return nil }
        let nodeByID = document.nodeByID
        let edges = document.edges.filter { $0.source == node.id || $0.target == node.id }
            .sorted { lhs, rhs in lhs.relation.localizedStandardCompare(rhs.relation) == .orderedAscending }
            .prefix(min(max(limit, 1), 120))
        return KajiCodeGraphNeighborResult(
            document: document,
            node: node,
            edges: edges.map { KajiCodeGraphNeighborEdge(edge: $0, source: nodeByID[$0.source], target: nodeByID[$0.target]) }
        )
    }

    static func path(
        graphURL: URL,
        from: KajiCodeGraphNodeQuery,
        to: KajiCodeGraphNodeQuery,
        maxDepth: Int
    ) throws -> KajiCodeGraphPathResult? {
        let document = try KajiCodeGraphDocumentLoader.load(url: graphURL)
        guard let source = resolveNode(document: document, query: from),
              let target = resolveNode(document: document, query: to)
        else { return nil }
        if source.id == target.id { return KajiCodeGraphPathResult(document: document, source: source, target: target, steps: []) }
        let depth = min(max(maxDepth, 1), 8)
        let adjacency = makeAdjacency(document: document)
        var queue: [(String, [KajiCodeGraphPathStep])] = [(source.id, [])]
        var seen: Set<String> = [source.id]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard current.1.count < depth else { continue }
            for step in adjacency[current.0] ?? [] {
                guard !seen.contains(step.node.id) else { continue }
                let nextSteps = current.1 + [step]
                if step.node.id == target.id { return KajiCodeGraphPathResult(
                    document: document,
                    source: source,
                    target: target,
                    steps: nextSteps
                ) }
                seen.insert(step.node.id)
                queue.append((step.node.id, nextSteps))
            }
        }
        return KajiCodeGraphPathResult(document: document, source: source, target: target, steps: nil)
    }

    static func hotspots(graphURL: URL, limit: Int) throws -> KajiCodeGraphHotspotResult {
        let document = try KajiCodeGraphDocumentLoader.load(url: graphURL)
        let nodes = document.nodes
            .sorted {
                if $0.degree != $1.degree { return $0.degree > $1.degree }
                return $0.label.localizedStandardCompare($1.label) == .orderedAscending
            }
            .prefix(min(max(limit, 1), 60))
        return KajiCodeGraphHotspotResult(document: document, nodes: Array(nodes))
    }

    private static func makeAdjacency(document: KajiCodeGraphDocument) -> [String: [KajiCodeGraphPathStep]] {
        let nodeByID = document.nodeByID
        var out: [String: [KajiCodeGraphPathStep]] = [:]
        for edge in document.edges.sorted(by: sortEdges) {
            if let target = nodeByID[edge.target] {
                out[edge.source, default: []].append(KajiCodeGraphPathStep(edge: edge, node: target, direction: "outgoing"))
            }
            if let source = nodeByID[edge.source] {
                out[edge.target, default: []].append(KajiCodeGraphPathStep(edge: edge, node: source, direction: "incoming"))
            }
        }
        return out
    }

    private static func score(node: KajiCodeGraphNode, terms: [String]) -> Int {
        let values = [node.id, node.label, node.sourceFile ?? "", node.fileType].map { $0.lowercased() }
        guard terms.allSatisfy({ term in values.contains(where: { $0.contains(term) }) }) else { return 0 }
        var score = 1
        for term in terms {
            if node.label.lowercased() == term { score += 80 }
            if node.id.lowercased() == term { score += 70 }
            if node.label.lowercased().hasPrefix(term) { score += 40 }
            if node.sourceFile?.lowercased().hasPrefix(term) == true { score += 30 }
            if node.sourceFile?.lowercased().contains(term) == true { score += 20 }
            if node.id.lowercased().contains(term) { score += 10 }
        }
        return score
    }

    private static func sortRankedNodes(_ lhs: KajiCodeGraphRankedNode, _ rhs: KajiCodeGraphRankedNode) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.node.degree != rhs.node.degree { return lhs.node.degree > rhs.node.degree }
        return lhs.node.label.localizedStandardCompare(rhs.node.label) == .orderedAscending
    }

    private static func sortEdges(_ lhs: KajiCodeGraphEdge, _ rhs: KajiCodeGraphEdge) -> Bool {
        if lhs.source != rhs.source { return lhs.source.localizedStandardCompare(rhs.source) == .orderedAscending }
        if lhs.target != rhs.target { return lhs.target.localizedStandardCompare(rhs.target) == .orderedAscending }
        return lhs.relation.localizedStandardCompare(rhs.relation) == .orderedAscending
    }

    private static func resolveNode(document: KajiCodeGraphDocument, query: KajiCodeGraphNodeQuery) -> KajiCodeGraphNode? {
        resolveNode(document: document, id: query.id, label: query.label, path: query.path)
    }

    private static func resolveNode(document: KajiCodeGraphDocument, id: String?, label: String?, path: String?) -> KajiCodeGraphNode? {
        let cleanID = id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let cleanLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.lowercased()
        let cleanPath = path?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.lowercased()
        if let cleanID, let node = document.nodeByID[cleanID] { return node }
        if let cleanLabel,
           let node = document.nodes.first(where: { $0.label.lowercased() == cleanLabel || $0.id.lowercased() == cleanLabel })
        {
            return node
        }
        if let cleanPath, let node = document.nodes.first(where: { ($0.sourceFile ?? "").lowercased() == cleanPath }) {
            return node
        }
        if let cleanPath, let node = document.nodes.first(where: { ($0.sourceFile ?? "").lowercased().hasSuffix(cleanPath) }) {
            return node
        }
        return nil
    }
}

private struct KajiCodeGraphRankedNode {
    let node: KajiCodeGraphNode
    let score: Int
}
