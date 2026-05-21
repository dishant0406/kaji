import Foundation

@MainActor
@Observable
final class KajiCodeGraphAgentSession: Identifiable {
    let id = UUID()
    let key: String
    let title: String
    let subtitle: String
    let controller: ParentAgentController
    let store: ParentAgentTaskStore

    init(key: String, title: String, subtitle: String, controller: ParentAgentController, store: ParentAgentTaskStore) {
        self.key = key
        self.title = title
        self.subtitle = subtitle
        self.controller = controller
        self.store = store
    }

    var status: ParentAgentTaskStatus {
        store.activeTask?.status ?? .planning
    }
}

@MainActor
@Observable
final class KajiCodeGraphAgentCoordinator {
    static let shared = KajiCodeGraphAgentCoordinator()

    var selectedSessionID: UUID?
    var sessions: [KajiCodeGraphAgentSession] = []
    var visibleKeys: Set<String> = []
    private let maxSessions: Int

    init(maxSessions: Int = 8) {
        self.maxSessions = max(1, maxSessions)
    }

    func start(
        request: KajiCodeGraphRunRequest,
        prompt: String,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) throws -> KajiCodeGraphAgentSession {
        let session = try makeSession(request: request, projectStore: projectStore)
        retain(session)
        session.store.clearActiveTask()
        session.controller.submit(
            prompt: prompt,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        return session
    }

    func select(_ session: KajiCodeGraphAgentSession) {
        selectedSessionID = session.id
        visibleKeys.insert(session.key)
    }

    func show(projectID: UUID, worktreeID: UUID) {
        let key = "\(projectID.uuidString)-\(worktreeID.uuidString)"
        visibleKeys.insert(key)
        if let session = sessions.first(where: { $0.key == key }) {
            select(session)
        }
    }

    func hasSession(projectID: UUID, worktreeID: UUID) -> Bool {
        let key = "\(projectID.uuidString)-\(worktreeID.uuidString)"
        return sessions.contains { $0.key == key }
    }

    func isVisible(projectID: UUID, worktreeID: UUID) -> Bool {
        visibleKeys.contains("\(projectID.uuidString)-\(worktreeID.uuidString)")
    }

    func session(projectID: UUID, worktreeID: UUID) -> KajiCodeGraphAgentSession? {
        let key = "\(projectID.uuidString)-\(worktreeID.uuidString)"
        return sessions.first { $0.key == key }
    }

    func hide(projectID: UUID, worktreeID: UUID) {
        visibleKeys.remove("\(projectID.uuidString)-\(worktreeID.uuidString)")
    }

    func close(_ session: KajiCodeGraphAgentSession) {
        session.controller.stop()
        sessions.removeAll { $0.id == session.id }
        visibleKeys.remove(session.key)
        if selectedSessionID == session.id {
            selectedSessionID = sessions.first?.id
        }
    }

    var selectedSession: KajiCodeGraphAgentSession? {
        if let selectedSessionID,
           let session = sessions.first(where: { $0.id == selectedSessionID })
        {
            return session
        }
        return sessions.first
    }

    func retain(_ session: KajiCodeGraphAgentSession) {
        let replaced = sessions.filter { $0.key == session.key && $0.id != session.id }
        replaced.forEach { $0.controller.stop() }
        sessions.removeAll { $0.key == session.key }
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
        visibleKeys.insert(session.key)
        pruneSessions()
    }

    private func pruneSessions() {
        guard sessions.count > maxSessions else { return }
        let evicted = Array(sessions.dropFirst(maxSessions))
        sessions = Array(sessions.prefix(maxSessions))
        for session in evicted {
            session.controller.stop()
            visibleKeys.remove(session.key)
            if selectedSessionID == session.id {
                selectedSessionID = sessions.first?.id
            }
        }
    }

    private func makeSession(
        request: KajiCodeGraphRunRequest,
        projectStore: ProjectStore
    ) throws -> KajiCodeGraphAgentSession {
        let directory = KajiCodeGraphDirectory.projectDirectory(projectID: request.projectID, worktreeID: request.worktreeID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let persistence = ParentAgentTaskPersistence(store: CodableFileStore(
            fileURL: directory.appendingPathComponent("graph-agent-tasks.json")
        ))
        let store = ParentAgentTaskStore(persistence: persistence)
        let controller = ParentAgentController(store: store)
        controller.process.environmentOverrides = try graphAgentEnvironment(request: request, directory: directory)
        let title = projectStore.projects.first { $0.id == request.projectID }?.name
            ?? URL(fileURLWithPath: request.projectPath).lastPathComponent
        return KajiCodeGraphAgentSession(
            key: "\(request.projectID.uuidString)-\(request.worktreeID.uuidString)",
            title: title,
            subtitle: request.mode.capitalized,
            controller: controller,
            store: store
        )
    }

    private func graphAgentEnvironment(request: KajiCodeGraphRunRequest, directory: URL) throws -> [String: String] {
        let work = KajiCodeGraphDirectory.graphOutputDirectory(projectID: request.projectID, worktreeID: request.worktreeID)
            .appendingPathComponent("agent-work", isDirectory: true)
        let graphifyOutput = work.appendingPathComponent("graphify-out", isDirectory: true)
        return try [
            "KAJI_PARENT_AGENT_MODE": "kajicodegraph",
            "GRAPHIFY_OUT": graphifyOutput.path,
            "KAJI_GRAPH_PROJECT_PATH": request.projectPath,
            "KAJI_GRAPH_WORK_DIR": work.path,
            "KAJI_GRAPH_READ_ROOTS": json([
                request.projectPath,
                directory.path,
                work.path,
                KajiCodeGraphDirectory.graphify.path,
            ]),
            "KAJI_GRAPH_WRITE_ROOTS": json([
                directory.path,
                work.path,
            ]),
            "KAJI_GRAPH_SHELL_ROOTS": json([
                directory.path,
                work.path,
            ]),
        ]
    }

    private func json(_ values: [String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: values, options: [])
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
