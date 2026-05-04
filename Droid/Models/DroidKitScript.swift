import Foundation

enum DroidKitScriptScope: String, Codable, CaseIterable, Hashable {
    case global
    case project
}

enum DroidKitScriptKind: String, Codable, CaseIterable, Hashable {
    case command
    case shellScript
}

enum DroidKitScriptDirectoryMode: String, Codable, CaseIterable, Hashable {
    case activeWorktree
    case projectRoot
    case home
}

enum DroidKitScriptConfirmation: String, Codable, CaseIterable, Hashable {
    case never
    case risky
    case always
}

struct DroidKitScript: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var slug: String
    var scope: DroidKitScriptScope
    var projectID: UUID?
    var kind: DroidKitScriptKind
    var command: String
    var directoryMode: DroidKitScriptDirectoryMode
    var confirmation: DroidKitScriptConfirmation
    var autoCloseOnSuccess: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        slug: String,
        scope: DroidKitScriptScope,
        projectID: UUID?,
        kind: DroidKitScriptKind,
        command: String,
        directoryMode: DroidKitScriptDirectoryMode = .activeWorktree,
        confirmation: DroidKitScriptConfirmation = .risky,
        autoCloseOnSuccess: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.scope = scope
        self.projectID = projectID
        self.kind = kind
        self.command = command
        self.directoryMode = directoryMode
        self.confirmation = confirmation
        self.autoCloseOnSuccess = autoCloseOnSuccess
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct DroidKitScriptRunPlan: Hashable {
    let script: DroidKitScript
    let workingDirectory: URL
    let runDirectory: URL
    let scriptURL: URL
}
