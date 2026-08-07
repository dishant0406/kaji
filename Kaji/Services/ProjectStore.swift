import Foundation
import os

private let logger = Logger(subsystem: "app.kaji", category: "ProjectStore")

@MainActor
@Observable
final class ProjectStore {
    private(set) var projects: [Project] = []
    private let persistence: any ProjectPersisting

    init(persistence: any ProjectPersisting) {
        self.persistence = persistence
        load()
    }

    func add(_ project: Project) {
        projects.append(project)
        _ = reindexSortOrder()
        save()
    }

    func nextSortOrder() -> Int {
        (projects.map(\.sortOrder).max() ?? -1) + 1
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        projects.removeAll { $0.id == id }
        _ = reindexSortOrder()
        return save()
    }

    private func reindexSortOrder() -> Bool {
        projects.sort { $0.sortOrder < $1.sortOrder }
        var changed = false
        for index in projects.indices where projects[index].sortOrder != index {
            projects[index].sortOrder = index
            changed = true
        }
        return changed
    }

    func rename(id: UUID, to newName: String) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].name = newName
        save()
    }

    func setLogo(id: UUID, to logo: String?) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        if logo == nil {
            ProjectLogoStorage.remove(forProjectID: id)
        }
        projects[index].logo = logo
        save()
    }

    func setIconColor(id: UUID, to color: String?) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].iconColor = color
        save()
    }

    func setVerificationCommand(id: UUID, to command: String?) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let normalized = command?.trimmingCharacters(in: .whitespacesAndNewlines)
        projects[index].verificationCommand = normalized?.isEmpty == false ? normalized : nil
        save()
    }

    func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        projects.move(fromOffsets: source, toOffset: destination)
        for index in projects.indices {
            projects[index].sortOrder = index
        }
        save()
    }

    @discardableResult
    func save() -> Bool {
        do {
            try persistence.saveProjects(projects)
            return true
        } catch {
            logger.error("Failed to save projects: \(error)")
            return false
        }
    }

    private func load() {
        do {
            projects = try persistence.loadProjects()
            if reindexSortOrder() {
                _ = save()
            }
        } catch {
            logger.error("Failed to load projects: \(error)")
        }
    }
}
