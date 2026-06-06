enum KajiAgentBasicHostToolDefinitions {
    static let definitions: [KajiAgentHostToolDefinition] = [
        KajiAgentHostToolDefinition(
            name: "kaji_get_active_context",
            label: "Kaji Context",
            description: "Get the active Kaji project and worktree.",
            parameters: .object(["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)]),
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
                "properties": .object(["title": .object(["type": .string("string")]), "command": .object(["type": .string("string")])]),
            ]),
            hidden: false,
            approval: "exec"
        ),
    ]
}
