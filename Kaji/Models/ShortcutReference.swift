import Foundation

struct ShortcutDefinition: Identifiable, Equatable {
    let action: ShortcutAction
    let displayName: String
    let category: String
    let scope: ShortcutScope
    let defaultCombo: KeyCombo?

    var id: ShortcutAction { action }
}

struct ShortcutReferenceGroup: Identifiable, Equatable {
    let title: String
    let actions: [ShortcutAction]

    var id: String { title }
}

struct CommandKReference: Identifiable, Equatable {
    let token: String
    let detail: String

    var id: String { token }
}

struct LocalShortcutReference: Identifiable, Equatable {
    let keys: String
    let name: String
    let category: String
    let context: String

    var id: String { "\(category):\(keys):\(name):\(context)" }
}

enum ShortcutReferenceCatalog {
    private static let payload = loadPayload()
    private static let definitionsByAction = Dictionary(uniqueKeysWithValues: payload.shortcuts.map { ($0.action, $0) })

    static var definitions: [ShortcutDefinition] {
        payload.shortcuts
    }

    static var actions: [ShortcutAction] {
        definitions.map(\.action)
    }

    static var categories: [String] {
        payload.categories
    }

    static var keyboardGroups: [ShortcutReferenceGroup] {
        categories.compactMap { category in
            let actions = definitions.filter { $0.category == category }.map(\.action)
            guard !actions.isEmpty else { return nil }
            return ShortcutReferenceGroup(title: category, actions: actions)
        }
    }

    static var keyboardActions: [ShortcutAction] {
        keyboardGroups.flatMap(\.actions)
    }

    static var commandKReferences: [CommandKReference] {
        payload.commandK
    }

    static var localShortcuts: [LocalShortcutReference] {
        payload.localShortcuts
    }

    static var defaultBindings: [KeyBinding] {
        definitions.compactMap { definition in
            guard let combo = definition.defaultCombo else { return nil }
            return KeyBinding(action: definition.action, combo: combo)
        }
    }

    static func definition(for action: ShortcutAction) -> ShortcutDefinition {
        guard let definition = definitionsByAction[action] else {
            fatalError("Missing shortcut definition for \(action.rawValue)")
        }
        return definition
    }

    private static func loadPayload() -> ShortcutReferencePayload {
        guard let url = Bundle.appResources.url(forResource: "shortcuts", withExtension: "json") else {
            fatalError("Missing shortcuts.json")
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ShortcutReferencePayload.self, from: data)
        } catch {
            fatalError("Invalid shortcuts.json: \(error)")
        }
    }
}

private struct ShortcutReferencePayload: Decodable {
    let categories: [String]
    let shortcuts: [ShortcutDefinition]
    let localShortcuts: [LocalShortcutReference]
    let commandK: [CommandKReference]
}

extension ShortcutDefinition: Decodable {
    private enum CodingKeys: String, CodingKey {
        case action
        case displayName
        case category
        case scope
        case defaultCombo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(ShortcutAction.self, forKey: .action)
        displayName = try container.decode(String.self, forKey: .displayName)
        category = try container.decode(String.self, forKey: .category)
        scope = try container.decode(ShortcutScope.self, forKey: .scope)
        defaultCombo = try container.decodeIfPresent(ShortcutDefaultCombo.self, forKey: .defaultCombo)?.keyCombo
    }
}

extension CommandKReference: Decodable {}

extension LocalShortcutReference: Decodable {}

private struct ShortcutDefaultCombo: Decodable {
    let key: String
    let command: Bool
    let shift: Bool
    let control: Bool
    let option: Bool

    var keyCombo: KeyCombo {
        KeyCombo(key: key, command: command, shift: shift, control: control, option: option)
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case command
        case shift
        case control
        case option
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        command = try container.decodeIfPresent(Bool.self, forKey: .command) ?? false
        shift = try container.decodeIfPresent(Bool.self, forKey: .shift) ?? false
        control = try container.decodeIfPresent(Bool.self, forKey: .control) ?? false
        option = try container.decodeIfPresent(Bool.self, forKey: .option) ?? false
    }
}
