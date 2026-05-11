import Foundation

enum KajiCodeGraphAgentPrompt {
    static func make(request: KajiCodeGraphRunRequest, output: URL, work: URL, buildID: String) -> String {
        let python = KajiCodeGraphDirectory.python.path
        let skill = skillURL.path
        let modeFlag = request.mode == "update" ? "--update" : ""

        return [
            "Build the Kaji Code Graph for this project using Graphify's agentic skill workflow.",
            "",
            "Target project: \(request.projectPath)",
            "Kaji output directory: \(output.path)",
            "Kaji work directory: \(work.path)",
            "Graphify skill source: \(skill)",
            "Kaji Graphify Python: \(python)",
            "",
            "Do not use the old AST-only shortcut.",
            "Do not choose or spawn Codex, Claude Code, OpenCode, Pi, or any other coding-agent CLI.",
            "Use your graph tools directly. Read the Graphify skill file at the path above and follow it as a plain instruction document.",
            "The Graphify skill does not need to be installed as a slash command.",
            "You must do semantic extraction, chunking, community labeling, and report generation yourself with the available graph tools.",
            "",
            "Graph-agent steps:",
            "1. Create \(work.path) and run every shell command with cwd \(work.path), not the project directory.",
            "2. Create \(work.path)/graphify-out/.graphify_python containing \(python).",
            "3. Follow the Graphify skill at \(skill).",
            "Adapt `/graphify \(request.projectPath) \(modeFlag) --no-viz` to write only into \(work.path)/graphify-out.",
            "If you invoke Graphify's CLI or Python module, include `--out \(work.path)`.",
            "Also export `GRAPHIFY_OUT=\(work.path)/graphify-out` before running Graphify.",
            "Never run Graphify with its default output path because that creates \(request.projectPath)/graphify-out.",
            "4. Keep project files untouched.",
            "Do not create AGENTS.md, CLAUDE.md, graphify-out, or hook files inside \(request.projectPath).",
            "5. Stop after Graphify produces graphify-out/graph.json and graphify-out/GRAPH_REPORT.md under \(work.path).",
            "",
            "Kaji will finalize and import the graph automatically when those files are ready.",
            "The Kaji UI is watching the generated files for buildID \(buildID).",
            "Do not report that no Kaji finalizer command was provided.",
        ].joined(separator: "\n")
    }

    static var skillURL: URL {
        let graphify = KajiCodeGraphDirectory.graphify.appendingPathComponent("graphify")
        let kaji = graphify.appendingPathComponent("skill-kaji.md")
        if FileManager.default.fileExists(atPath: kaji.path) {
            return kaji
        }
        return graphify.appendingPathComponent("skill.md")
    }
}
