import Foundation

enum AppCommandRegistry {
    static var commands: [AppCommand] {
        ShortcutReferenceCatalog.definitions.map(AppCommand.init(shortcut:))
    }

    static var editorCommands: [AppCommand] {
        commands.filter { $0.category == "Editor" }
    }

    static func command(for action: ShortcutAction) -> AppCommand {
        AppCommand(shortcut: ShortcutReferenceCatalog.definition(for: action))
    }

    static func search(_ query: String, in commands: [AppCommand] = commands) -> [AppCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return commands }
        return commands
            .map { command in (command, score(command, query: trimmed)) }
            .filter { $0.1 != nil }
            .sorted { ($0.1 ?? 0) > ($1.1 ?? 0) }
            .map(\.0)
    }

    private static func score(_ command: AppCommand, query: String) -> Int? {
        let title = command.title.lowercased()
        let category = command.category.lowercased()
        if title == query { return 1000 }
        if title.hasPrefix(query) { return 800 - title.count }
        if title.contains(query) { return 600 - title.count }
        if category.contains(query) { return 300 - title.count }
        return fuzzyScore(title, query: query)
    }

    private static func fuzzyScore(_ value: String, query: String) -> Int? {
        var index = value.startIndex
        var score = 0
        for character in query {
            guard let found = value[index...].firstIndex(of: character) else { return nil }
            score += found == index ? 12 : 4
            index = value.index(after: found)
        }
        return score
    }
}
