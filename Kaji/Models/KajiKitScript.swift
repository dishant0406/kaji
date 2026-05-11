import Foundation

enum KajiKitScriptScope: String, Codable, CaseIterable, Hashable {
    case global
    case project
}

enum KajiKitScriptKind: String, Codable, CaseIterable, Hashable {
    case command
    case shellScript
}

enum KajiKitScriptDirectoryMode: String, Codable, CaseIterable, Hashable {
    case activeWorktree
    case projectRoot
    case home
}

enum KajiKitScriptConfirmation: String, Codable, CaseIterable, Hashable {
    case never
    case risky
    case always
}

struct KajiKitScript: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var slug: String
    var scope: KajiKitScriptScope
    var projectID: UUID?
    var kind: KajiKitScriptKind
    var command: String
    var directoryMode: KajiKitScriptDirectoryMode
    var confirmation: KajiKitScriptConfirmation
    var autoCloseOnSuccess: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        slug: String,
        scope: KajiKitScriptScope,
        projectID: UUID?,
        kind: KajiKitScriptKind,
        command: String,
        directoryMode: KajiKitScriptDirectoryMode = .activeWorktree,
        confirmation: KajiKitScriptConfirmation = .risky,
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

struct KajiKitScriptRunPlan: Hashable {
    let script: KajiKitScript
    let workingDirectory: URL
    let runDirectory: URL
    let scriptURL: URL
}
