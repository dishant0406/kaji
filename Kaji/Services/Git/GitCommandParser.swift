import Foundation

enum GitCommandParser {
    enum ParseError: LocalizedError, Hashable {
        case unterminatedQuote

        var errorDescription: String? {
            switch self {
            case .unterminatedQuote:
                "Unterminated quoted argument."
            }
        }
    }

    static func state(for text: String) -> GitCommandPaletteState? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(":") else { return nil }
        let body = String(trimmed.dropFirst())
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let token = parts.first?.lowercased(),
              let command = GitPaletteCommand.allCases.first(where: { $0.rawValue == token })
        else { return nil }
        let filter = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return GitCommandPaletteState(command: command, filter: filter)
    }

    static func request(command: GitPaletteCommand, input: String) -> GitCommandRequest {
        do {
            let parsed = try arguments(from: input)
            let arguments: [String] = switch command {
            case .git:
                parsed
            case .branch:
                parsed.isEmpty ? ["branch", "--list"] : ["branch", "--list"] + parsed
            case .switchBranch:
                ["switch"] + parsed
            case .checkout:
                ["checkout"] + parsed
            }
            return request(arguments: arguments)
        } catch {
            let display = command == .git ? "git \(input)" : "git \(command.rawValue) \(input)"
            return GitCommandRequest(
                arguments: [],
                displayCommand: display.trimmingCharacters(in: .whitespacesAndNewlines),
                confirmationMessage: nil,
                blockedMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                refreshesRepository: false
            )
        }
    }

    static func request(arguments: [String]) -> GitCommandRequest {
        let display = "git \(arguments.joined(separator: " "))".trimmingCharacters(in: .whitespacesAndNewlines)
        return GitCommandRequest(
            arguments: arguments,
            displayCommand: display,
            confirmationMessage: confirmationMessage(for: arguments),
            blockedMessage: blockedMessage(for: arguments),
            refreshesRepository: refreshesRepository(arguments)
        )
    }

    static var commonRequests: [GitCommandRequest] {
        [
            ["status", "--short", "--branch"],
            ["fetch"],
            ["pull"],
            ["push"],
            ["branch", "--list"],
            ["log", "--oneline", "-20"],
            ["diff", "--stat"],
        ].map(request(arguments:))
    }

    static func arguments(from raw: String) throws -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false

        for character in raw {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character.isWhitespace {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }

        if escaped {
            current.append("\\")
        }
        if quote != nil {
            throw ParseError.unterminatedQuote
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static func blockedMessage(for arguments: [String]) -> String? {
        guard let subcommand = arguments.first else { return "Enter a git command to run." }
        if subcommand == "commit", !arguments.contains("-m"), !arguments.contains("--message") {
            return "Use git commit -m \"message\" here, or run interactive commits in a terminal."
        }
        if subcommand == "rebase", arguments.contains("-i") || arguments.contains("--interactive") {
            return "Interactive rebase needs a real terminal."
        }
        if subcommand == "add", arguments.contains("-p") || arguments.contains("--patch") {
            return "Patch mode needs a real terminal."
        }
        return nil
    }

    private static func confirmationMessage(for arguments: [String]) -> String? {
        guard let subcommand = arguments.first else { return nil }
        if subcommand == "reset", arguments.contains("--hard") {
            return "This will discard local changes. Run it anyway?"
        }
        if subcommand == "clean", cleanArgumentsAreDestructive(arguments) {
            return "This will delete untracked files. Run it anyway?"
        }
        if subcommand == "push", arguments.contains("--force") || arguments.contains("--force-with-lease") || arguments.contains("-f") {
            return "This force push can rewrite remote history. Run it anyway?"
        }
        if subcommand == "branch", arguments.contains("-D") {
            return "This will delete a local branch even if it is unmerged. Run it anyway?"
        }
        return nil
    }

    private static func cleanArgumentsAreDestructive(_ arguments: [String]) -> Bool {
        let flags = arguments.filter { $0.hasPrefix("-") }.joined()
        return flags.contains("f") && flags.contains("d")
    }

    private static func refreshesRepository(_ arguments: [String]) -> Bool {
        guard let subcommand = arguments.first else { return false }
        return [
            "add", "branch", "checkout", "cherry-pick", "clean", "commit", "fetch",
            "merge", "pull", "push", "rebase", "reset", "restore", "revert", "rm",
            "stash", "switch", "tag",
        ].contains(subcommand)
    }
}
