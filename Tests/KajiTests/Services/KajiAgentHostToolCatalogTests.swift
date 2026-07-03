import Testing

@testable import Kaji

struct KajiAgentHostToolCatalogTests {
    @Test
    func exposesWorkspaceHostToolsWithoutCodeGraphInjection() {
        let definitions = Dictionary(uniqueKeysWithValues: KajiAgentHostToolCatalog.definitions.map { ($0.name, $0) })

        #expect(definitions["kaji_get_open_tabs"]?.approval == "read")
        #expect(definitions["kaji_get_editor_selection"]?.approval == "read")
        #expect(definitions["kaji_get_visible_file_context"]?.approval == "read")
        #expect(definitions["kaji_get_terminal_panes"]?.approval == "read")
        #expect(definitions["kaji_get_worktree_status"]?.approval == "read")
        #expect(definitions["kaji_show_diff"]?.approval == "read")
        #expect(definitions["kaji_open_diff"]?.approval == "read")
        #expect(definitions["kaji_focus_file_range"]?.approval == "read")
        #expect(definitions["kaji_report_diagnostics"]?.approval == "read")
        #expect(definitions["kaji_code_graph_status"] == nil)
        #expect(definitions["kaji_code_graph_search"] == nil)
        #expect(definitions["kaji_focus_file_range"]?.parameters.objectValue?["required"]?.arrayValue == [.string("path")])
        #expect(definitions["kaji_show_diff"]?.parameters.objectValue?["properties"]?.objectValue?["lineLimit"] != nil)
    }
}
