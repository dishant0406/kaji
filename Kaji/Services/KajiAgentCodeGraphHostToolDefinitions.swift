enum KajiAgentCodeGraphHostToolDefinitions {
    static let definitions: [KajiAgentHostToolDefinition] = [status, report, search, neighbors, path, hotspots]

    private static let status = KajiAgentHostToolDefinition(
        name: "kaji_code_graph_status",
        label: "Code Graph Status",
        description: "Check whether the active worktree KajiCodeGraph artifacts exist without treating missing artifacts as an error.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false),
        ]),
        hidden: false,
        approval: "read"
    )

    private static let report = KajiAgentHostToolDefinition(
        name: "kaji_code_graph_report",
        label: "Code Graph Report",
        description: "Read the active worktree KajiCodeGraph architecture report after kaji_code_graph_status reports ready.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object(["max_lines": .object(["type": .string("number")])]),
            "additionalProperties": .bool(false),
        ]),
        hidden: false,
        approval: "read"
    )

    private static let search = KajiAgentHostToolDefinition(
        name: "kaji_code_graph_search",
        label: "Code Graph Search",
        description: "Search active worktree KajiCodeGraph nodes after kaji_code_graph_status reports ready.",
        parameters: queryParameters("Symbol, file, or architectural term", "Maximum nodes, default 20"),
        hidden: false,
        approval: "read"
    )

    private static let neighbors = KajiAgentHostToolDefinition(
        name: "kaji_code_graph_neighbors",
        label: "Code Graph Neighbors",
        description: "Show incoming and outgoing dependency edges for an active worktree KajiCodeGraph node.",
        parameters: nodeParameters(extra: ["limit": .object(["type": .string("number")])]),
        hidden: false,
        approval: "read"
    )

    private static let path = KajiAgentHostToolDefinition(
        name: "kaji_code_graph_path",
        label: "Code Graph Path",
        description: "Find the shortest relationship path between two active worktree KajiCodeGraph nodes.",
        parameters: pathParameters,
        hidden: false,
        approval: "read"
    )

    private static let hotspots = KajiAgentHostToolDefinition(
        name: "kaji_code_graph_hotspots",
        label: "Code Graph Hotspots",
        description: "List high-degree KajiCodeGraph nodes that are likely architecture entry points.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object(["limit": .object(["type": .string("number")])]),
            "additionalProperties": .bool(false),
        ]),
        hidden: false,
        approval: "read"
    )

    private static var pathParameters: KajiAgentJSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "from_id": .object(["type": .string("string")]), "from_label": .object(["type": .string("string")]),
                "from_path": .object(["type": .string("string")]),
                "to_id": .object(["type": .string("string")]), "to_label": .object(["type": .string("string")]),
                "to_path": .object(["type": .string("string")]),
                "max_depth": .object(["type": .string("number")]),
            ]),
            "additionalProperties": .bool(false),
        ])
    }

    private static func queryParameters(_ queryDescription: String, _ limitDescription: String) -> KajiAgentJSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string"), "description": .string(queryDescription)]),
                "limit": .object(["type": .string("number"), "description": .string(limitDescription)]),
            ]),
            "required": .array([.string("query")]),
            "additionalProperties": .bool(false),
        ])
    }

    private static func nodeParameters(extra: [String: KajiAgentJSONValue]) -> KajiAgentJSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string")]),
                "label": .object(["type": .string("string")]),
                "path": .object(["type": .string("string")]),
            ].merging(extra) { lhs, _ in lhs }),
            "additionalProperties": .bool(false),
        ])
    }
}
