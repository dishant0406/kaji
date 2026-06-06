extension KajiAgentTranscriptRestorer {
    struct ToolLocation {
        let turn: Int
        let block: Int
        let tool: Int
    }

    func toolLocation(id: String) -> ToolLocation? {
        for turnIndex in turns.indices.reversed() {
            for blockIndex in turns[turnIndex].blocks.indices.reversed() {
                guard case let .toolGroup(group) = turns[turnIndex].blocks[blockIndex],
                      let toolIndex = group.tools.lastIndex(where: { $0.toolCallID == id })
                else { continue }
                return ToolLocation(turn: turnIndex, block: blockIndex, tool: toolIndex)
            }
        }
        return nil
    }

    mutating func updateTool(at location: ToolLocation, mutate: (inout KajiAgentMessage) -> Void) {
        guard case var .toolGroup(group) = turns[location.turn].blocks[location.block],
              group.tools.indices.contains(location.tool)
        else { return }
        mutate(&group.tools[location.tool])
        turns[location.turn].blocks[location.block] = .toolGroup(group)
    }

    mutating func updateToolOutput(at location: ToolLocation, output: String?, complete: Bool) {
        guard let output, !output.isEmpty else { return }
        let toolName = tool(at: location)?.title ?? "Tool"
        let preview = KajiAgentToolOutputPreview.make(from: output, toolName: toolName, complete: complete)
        updateTool(at: location) { tool in
            tool.detail = preview.summary
            tool.preview = preview.preview
            tool.fullOutput = preview.fullOutput
            tool.truncatedLineCount = preview.truncatedLineCount
        }
    }

    func tool(at location: ToolLocation) -> KajiAgentMessage? {
        guard case let .toolGroup(group) = turns[location.turn].blocks[location.block],
              group.tools.indices.contains(location.tool)
        else { return nil }
        return group.tools[location.tool]
    }
}
