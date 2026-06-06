enum KajiAgentWorkspaceHostToolDefinitions {
    static let definitions: [KajiAgentHostToolDefinition] = [
        definition("kaji_get_open_tabs", "Open Tabs", "List open Kaji tabs for the active project and identify the active tab."),
        definition(
            "kaji_get_editor_selection",
            "Editor Selection",
            "Read the selected text and cursor position from the active native editor."
        ),
        definition(
            "kaji_get_visible_file_context",
            "Visible File Context",
            "Read the active native editor, diff, preview, or pane context."
        ),
        definition("kaji_get_terminal_panes", "Terminal Panes", "List open Kaji terminal panes in the active project."),
        definition("kaji_get_worktree_status", "Worktree Status", "Read the active Kaji worktree git branch and short status."),
        showDiffDefinition,
        openDiffDefinition,
        focusFileRangeDefinition,
        definition("kaji_report_diagnostics", "Diagnostics", "Report native editor diagnostics for the active worktree."),
    ]

    private static let showDiffDefinition = KajiAgentHostToolDefinition(
        name: "kaji_show_diff",
        label: "Show Diff",
        description: "Return the active worktree git diff, optionally scoped to a file path.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string")]),
                "lineLimit": .object(["type": .string("number")]),
            ]),
            "additionalProperties": .bool(false),
        ]),
        hidden: false,
        approval: "read"
    )

    private static let openDiffDefinition = KajiAgentHostToolDefinition(
        name: "kaji_open_diff",
        label: "Open Diff",
        description: "Open Kaji's native diff viewer for all changes or a specific file path.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string")]),
                "isStaged": .object(["type": .string("boolean")]),
            ]),
            "additionalProperties": .bool(false),
        ]),
        hidden: false,
        approval: "read"
    )

    private static let focusFileRangeDefinition = KajiAgentHostToolDefinition(
        name: "kaji_focus_file_range",
        label: "Focus File Range",
        description: "Open a file in Kaji's native editor and focus a one-based line and column.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string")]),
                "line": .object(["type": .string("number")]),
                "column": .object(["type": .string("number")]),
            ]),
            "required": .array([.string("path")]),
            "additionalProperties": .bool(false),
        ]),
        hidden: false,
        approval: "read"
    )

    private static func definition(_ name: String, _ label: String, _ description: String) -> KajiAgentHostToolDefinition {
        KajiAgentHostToolDefinition(
            name: name,
            label: label,
            description: description,
            parameters: .object(["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)]),
            hidden: false,
            approval: "read"
        )
    }
}
