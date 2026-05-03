import Foundation

struct ParentAgentTaskSnapshot: Codable {
    var tasks: [ParentAgentTask]
    var activeTaskID: UUID?
}

struct ParentAgentTaskPersistence {
    private let store: CodableFileStore<ParentAgentTaskSnapshot>

    init(
        store: CodableFileStore<ParentAgentTaskSnapshot> = CodableFileStore(
            fileURL: DroidFileStorage.fileURL(filename: "parent-agent-tasks.json")
        )
    ) {
        self.store = store
    }

    func load() throws -> ParentAgentTaskSnapshot? {
        try store.load()
    }

    func save(tasks: [ParentAgentTask], activeTaskID: UUID?) throws {
        try store.save(ParentAgentTaskSnapshot(tasks: tasks, activeTaskID: activeTaskID))
    }
}
