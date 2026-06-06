enum KajiAgentHostToolCatalog {
    static let definitions: [KajiAgentHostToolDefinition] = [
        KajiAgentHostToolDefinition(
            name: "kaji_get_active_context",
            label: "Kaji Context",
            description: "Get the active Kaji project and worktree.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false),
            ]),
            hidden: false,
            approval: "read"
        ),
        KajiAgentHostToolDefinition(
            name: "kaji_open_file",
            label: "Open File",
            description: "Open a file in Kaji's native editor. Pass path as an absolute path or project-relative path.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object(["path": .object(["type": .string("string")])]),
                "required": .array([.string("path")]),
            ]),
            hidden: false,
            approval: "read"
        ),
        KajiAgentHostToolDefinition(
            name: "kaji_open_terminal",
            label: "Open Terminal",
            description: "Open a native Kaji terminal or command tab in the active project.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "title": .object(["type": .string("string")]),
                    "command": .object(["type": .string("string")]),
                ]),
            ]),
            hidden: false,
            approval: "exec"
        ),
        KajiAgentHostToolDefinition(
            name: "kaji_fff_find",
            label: "FFF File Search",
            description: [
                "Fast Kaji-native fuzzy file search powered by FFF.",
                "Prefer this over broad find/glob for fuzzy paths, symbol-like names, or partial filenames.",
            ].joined(separator: " "),
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string"), "description": .string("Fuzzy file query")]),
                    "limit": .object(["type": .string("number"), "description": .string("Maximum results, default 30")]),
                ]),
                "required": .array([.string("query")]),
                "additionalProperties": .bool(false),
            ]),
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
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string"), "description": .string("Text query to search for")]),
                    "limit": .object(["type": .string("number"), "description": .string("Maximum matches, default 120")]),
                ]),
                "required": .array([.string("query")]),
                "additionalProperties": .bool(false),
            ]),
            hidden: false,
            approval: "read"
        ),
    ]

    static let uriSchemes: [KajiAgentHostURISchemeDefinition] = [
        KajiAgentHostURISchemeDefinition(
            scheme: "kaji-file",
            description: "Read files from the active Kaji workspace.",
            writable: false,
            immutable: false
        ),
    ]
}
