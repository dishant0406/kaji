import Foundation
import Testing

@testable import Kaji

@Suite("Project store sort order")
@MainActor
struct ProjectStoreTests {
    @Test("add assigns the next sequential sort order")
    func addAssignsNextSortOrder() {
        let store = ProjectStore(persistence: MemoryProjectPersistence(projects: [
            Project(name: "A", path: "/tmp/a", sortOrder: 0),
            Project(name: "B", path: "/tmp/b", sortOrder: 1),
        ]))

        store.add(Project(name: "C", path: "/tmp/c", sortOrder: 99))

        #expect(store.projects.map(\.sortOrder) == [0, 1, 2])
    }

    @Test("remove reindexes remaining projects into a contiguous sequence")
    func removeReindexesSortOrders() {
        let store = ProjectStore(persistence: MemoryProjectPersistence(projects: [
            Project(name: "A", path: "/tmp/a", sortOrder: 0),
            Project(name: "B", path: "/tmp/b", sortOrder: 1),
            Project(name: "C", path: "/tmp/c", sortOrder: 2),
        ]))

        let removed = store.projects[1]
        store.remove(id: removed.id)

        #expect(store.projects.map(\.sortOrder) == [0, 1])
        #expect(store.projects.map(\.name) == ["A", "C"])
    }

    @Test("load reindexes legacy sort orders with gaps and duplicates")
    func loadNormalizesLegacySortOrders() {
        let persistence = MemoryProjectPersistence(projects: [
            Project(name: "A", path: "/tmp/a", sortOrder: 0),
            Project(name: "B", path: "/tmp/b", sortOrder: 10),
            Project(name: "C", path: "/tmp/c", sortOrder: 10),
            Project(name: "D", path: "/tmp/d", sortOrder: 9),
        ])

        let store = ProjectStore(persistence: persistence)

        #expect(store.projects.map(\.sortOrder) == [0, 1, 2, 3])
        #expect(persistence.savedProjects.last?.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test("add after removals does not reuse a stale sort order")
    func addAfterRemovalKeepsUniqueSortOrder() {
        let store = ProjectStore(persistence: MemoryProjectPersistence(projects: [
            Project(name: "A", path: "/tmp/a", sortOrder: 0),
            Project(name: "B", path: "/tmp/b", sortOrder: 1),
        ]))
        store.remove(id: store.projects[1].id)

        store.add(Project(name: "C", path: "/tmp/c", sortOrder: 99))

        #expect(store.projects.map(\.sortOrder) == [0, 1])
    }
}

private final class MemoryProjectPersistence: ProjectPersisting {
    var projects: [Project]
    var savedProjects: [[Project]] = []

    init(projects: [Project]) {
        self.projects = projects
    }

    func loadProjects() throws -> [Project] {
        projects
    }

    func saveProjects(_ projects: [Project]) throws {
        savedProjects.append(projects)
        self.projects = projects
    }
}
