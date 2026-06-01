import Foundation

@MainActor
enum KajiAgentHostToolRegistry {
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
            hidden: false
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
            hidden: false
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
            hidden: false
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

    static func execute(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        switch frame.toolName {
        case "kaji_get_active_context":
            return activeContext(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_open_file":
            return openFile(frame, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_open_terminal":
            return openTerminal(frame, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        default:
            return error("Unsupported Kaji host tool: \(frame.toolName ?? "unknown")")
        }
    }

    static func resolveURI(_ frame: KajiAgentRPCFrame, appState: AppState?, projectStore: ProjectStore?, worktreeStore: WorktreeStore?) -> KajiAgentHostURIResult {
        guard frame.operation == "read", let url = frame.url, url.hasPrefix("kaji-file://") else {
            return .failure("Unsupported Kaji URI request.")
        }
        guard let context = activeWorkspace(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore) else {
            return .failure("No active Kaji project.")
        }
        let path = String(url.dropFirst("kaji-file://".count)).removingPercentEncoding ?? ""
        guard !path.isEmpty else { return .failure("Missing file path.") }
        guard let safePath = safeWorkspacePath(path, rootPath: context.worktree.path) else {
            return .failure("File path is outside the active Kaji worktree.")
        }
        do {
            let text = try String(contentsOfFile: safePath, encoding: .utf8)
            return .success(content: text, contentType: "text/plain")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func activeContext(appState: AppState?, projectStore: ProjectStore?, worktreeStore: WorktreeStore?) -> KajiAgentToolResult {
        guard let context = activeWorkspace(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore) else {
            return error("No active Kaji project.")
        }
        return text("Active project: \(context.project.name)\nProject path: \(context.project.path)\nWorktree: \(context.worktree.name)\nWorktree path: \(context.worktree.path)")
    }

    private static func openFile(_ frame: KajiAgentRPCFrame, appState: AppState?, projectStore: ProjectStore?, worktreeStore: WorktreeStore?) -> KajiAgentToolResult {
        guard let context = activeWorkspace(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore) else {
            return error("No active Kaji project.")
        }
        guard let rawPath = frame.arguments?["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty else {
            return error("path is required.")
        }
        guard let path = safeWorkspacePath(rawPath, rootPath: context.worktree.path) else {
            return error("File path is outside the active Kaji worktree.")
        }
        context.appState.selectProject(context.project, worktree: context.worktree)
        context.appState.openFile(path, projectID: context.project.id)
        return text("Opened \(path).")
    }

    private static func openTerminal(_ frame: KajiAgentRPCFrame, appState: AppState?, projectStore: ProjectStore?, worktreeStore: WorktreeStore?) -> KajiAgentToolResult {
        guard let context = activeWorkspace(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore) else {
            return error("No active Kaji project.")
        }
        let title = frame.arguments?["title"]?.stringValue?.nilIfEmpty ?? "Terminal"
        let command = frame.arguments?["command"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        context.appState.selectProject(context.project, worktree: context.worktree)
        if command.isEmpty {
            context.appState.createTab(projectID: context.project.id)
        } else {
            context.appState.createCommandTab(projectID: context.project.id, title: title, command: command)
        }
        return text(command.isEmpty ? "Opened terminal." : "Opened command terminal.")
    }

    private static func activeWorkspace(appState: AppState?, projectStore: ProjectStore?, worktreeStore: WorktreeStore?) -> KajiAgentWorkspaceContext? {
        guard let appState, let projectStore, let worktreeStore,
              let projectID = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == projectID })
        else { return nil }
        worktreeStore.ensurePrimary(for: project)
        let worktree = appState.activeWorktreeKey(for: project.id)
            .flatMap { worktreeStore.worktree(projectID: project.id, worktreeID: $0.worktreeID) }
            ?? worktreeStore.primary(for: project.id)
            ?? Worktree(name: project.name, path: project.path, isPrimary: true)
        return KajiAgentWorkspaceContext(appState: appState, project: project, worktree: worktree)
    }

    private static func text(_ value: String) -> KajiAgentToolResult {
        KajiAgentToolResult(content: [KajiAgentContentBlock(type: "text", text: value)], details: nil, isError: false)
    }

    private static func error(_ value: String) -> KajiAgentToolResult {
        KajiAgentToolResult(content: [KajiAgentContentBlock(type: "text", text: value)], details: nil, isError: true)
    }

    private static func safeWorkspacePath(_ rawPath: String, rootPath: String) -> String? {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let candidate = rawPath.hasPrefix("/")
            ? URL(fileURLWithPath: rawPath)
            : root.appendingPathComponent(rawPath)
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else { return nil }
        return resolved.path
    }
}

private struct KajiAgentWorkspaceContext {
    let appState: AppState
    let project: Project
    let worktree: Worktree
}

struct KajiAgentHostURIResult {
    let content: String?
    let contentType: String?
    let error: String?

    static func success(content: String, contentType: String) -> Self {
        Self(content: content, contentType: contentType, error: nil)
    }

    static func failure(_ error: String) -> Self {
        Self(content: nil, contentType: nil, error: error)
    }

    func response(id: String) -> KajiAgentRPCFrame {
        KajiAgentRPCFrame(
            id: id,
            type: "host_uri_result",
            error: error,
            isError: error != nil,
            content: content,
            contentType: contentType
        )
    }
}
