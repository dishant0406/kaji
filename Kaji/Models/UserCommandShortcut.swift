import Foundation

struct UserCommandShortcut: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var slug: String
    var command: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        slug: String,
        command: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.command = command
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct UserCommandShortcutDraft: Hashable {
    var id: UUID?
    var name = ""
    var slug = ""
    var command = ""

    init() {}

    init(shortcut: UserCommandShortcut) {
        id = shortcut.id
        name = shortcut.name
        slug = shortcut.slug
        command = shortcut.command
    }
}

enum UserCommandShortcutValidationError: Hashable {
    case nameRequired
    case slugRequired
    case slugInvalid
    case slugConflict
    case slugReserved
    case commandRequired
    case templateInvalid(String)

    var message: String {
        switch self {
        case .nameRequired:
            "Name is required."
        case .slugRequired:
            "Slug is required."
        case .slugInvalid:
            "Slug can only use lowercase letters and numbers."
        case .slugConflict:
            "Slug already exists."
        case .slugReserved:
            "Slug is reserved by a built-in Command-K shortcut."
        case .commandRequired:
            "Command is required."
        case let .templateInvalid(message):
            message
        }
    }
}

struct UserCommandShortcutValidation: Hashable {
    let errors: [UserCommandShortcutValidationError]

    var canSave: Bool {
        errors.isEmpty
    }
}
