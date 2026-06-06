import Testing

@testable import Kaji

struct KajiAgentHostToolCatalogTests {
    @Test
    func exposesCodeGraphToolsAsReadOnlyHostTools() {
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
        #expect(definitions["kaji_code_graph_status"]?.approval == "read")
        #expect(definitions["kaji_code_graph_report"]?.approval == "read")
        #expect(definitions["kaji_code_graph_search"]?.approval == "read")
        #expect(definitions["kaji_code_graph_neighbors"]?.approval == "read")
        #expect(definitions["kaji_code_graph_path"]?.approval == "read")
        #expect(definitions["kaji_code_graph_hotspots"]?.approval == "read")
        #expect(definitions["kaji_code_graph_search"]?.parameters.objectValue?["required"]?.arrayValue == [.string("query")])
        #expect(definitions["kaji_code_graph_status"]?.parameters.objectValue?["additionalProperties"]?.boolValue == false)
        #expect(definitions["kaji_focus_file_range"]?.parameters.objectValue?["required"]?.arrayValue == [.string("path")])
        #expect(definitions["kaji_show_diff"]?.parameters.objectValue?["properties"]?.objectValue?["lineLimit"] != nil)
    }
}
