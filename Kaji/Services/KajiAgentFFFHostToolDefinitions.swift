enum KajiAgentFFFHostToolDefinitions {
    static let definitions: [KajiAgentHostToolDefinition] = [
        KajiAgentHostToolDefinition(
            name: "kaji_fff_find",
            label: "FFF File Search",
            description: [
                "Fast Kaji-native fuzzy file search powered by FFF.",
                "Prefer this over broad find/glob for fuzzy paths, symbol-like names, or partial filenames.",
            ].joined(separator: " "),
            parameters: textQueryParameters("Fuzzy file query", "Maximum results, default 30"),
            hidden: false,
            approval: "read"
        ),
        KajiAgentHostToolDefinition(
            name: "kaji_fff_search",
            label: "FFF Text Search",
            description: [
                "Fast Kaji-native repository content search powered by FFF live grep.",
                "Prefer this for broad active-worktree text search when exact grep flags are not required.",
            ].joined(separator: " "),
            parameters: textQueryParameters("Text query to search for", "Maximum matches, default 120"),
            hidden: false,
            approval: "read"
        ),
    ]

    private static func textQueryParameters(_ queryDescription: String, _ limitDescription: String) -> KajiAgentJSONValue {
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
}
