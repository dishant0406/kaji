import Foundation

enum DroidCodeGraphAgentPrompt {
    static func make(request: DroidCodeGraphRunRequest, output: URL, work: URL, buildID: String) -> String {
        let python = DroidCodeGraphDirectory.python.path
        let skill = skillURL.path
        let modeFlag = request.mode == "update" ? "--update" : ""

        return [
            "Build the Droid Code Graph for this project using Graphify's agentic skill workflow.",
            "",
            "Target project: \(request.projectPath)",
            "Droid output directory: \(output.path)",
            "Droid work directory: \(work.path)",
            "Graphify skill source: \(skill)",
            "Droid Graphify Python: \(python)",
            "",
            "Do not use the old AST-only shortcut.",
            "Do not choose or spawn Codex, Claude Code, OpenCode, Pi, or any other coding-agent CLI.",
            "Use your graph tools directly. Read the Graphify skill file at the path above and follow it as a plain instruction document.",
            "The Graphify skill does not need to be installed as a slash command.",
            "You must do semantic extraction, chunking, community labeling, and report generation yourself with the available graph tools.",
            "",
            "Graph-agent steps:",
            "1. Create \(work.path) and run all Graphify temporary work from that directory, not from the project directory.",
            "2. Create \(work.path)/graphify-out/.graphify_python containing \(python).",
            "3. Follow the Graphify skill at \(skill).",
            "Adapt `/graphify \(request.projectPath) \(modeFlag) --no-viz` so every `graphify-out` path stays under \(work.path).",
            "4. Keep project files untouched.",
            "Do not create AGENTS.md, CLAUDE.md, graphify-out, or hook files inside \(request.projectPath).",
            "5. Stop after Graphify produces graphify-out/graph.json and graphify-out/GRAPH_REPORT.md under \(work.path).",
            "",
            "Droid will finalize and import the graph automatically when those files are ready.",
            "The Droid UI is watching the generated files for buildID \(buildID).",
            "Do not report that no Droid finalizer command was provided.",
        ].joined(separator: "\n")
    }

    static var skillURL: URL {
        let graphify = DroidCodeGraphDirectory.graphify.appendingPathComponent("graphify")
        let droid = graphify.appendingPathComponent("skill-droid.md")
        if FileManager.default.fileExists(atPath: droid.path) {
            return droid
        }
        return graphify.appendingPathComponent("skill.md")
    }
}
