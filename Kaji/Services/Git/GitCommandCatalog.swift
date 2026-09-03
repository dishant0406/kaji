import Foundation

enum GitCommandEffect: Hashable {
    case readOnly
    case mutating
    case destructive
    case interactive
}

enum GitCommandPresentation: Hashable {
    case branchList
    case commitLog
    case statusList
    case plainOutput
}

struct GitCommandDescriptor: Hashable {
    let effect: GitCommandEffect
    let presentation: GitCommandPresentation?

    var autoPreviews: Bool {
        effect == .readOnly && presentation != nil
    }
}

enum GitCommandCatalog {
    static func descriptor(for arguments: [String]) -> GitCommandDescriptor {
        guard let subcommand = arguments.first else {
            return GitCommandDescriptor(effect: .interactive, presentation: nil)
        }
        if subcommand == "stash" {
            let presentation: GitCommandPresentation? = arguments.dropFirst().first == "list" ? .plainOutput : nil
            return GitCommandDescriptor(effect: presentation == nil ? .mutating : .readOnly, presentation: presentation)
        }
        if subcommand == "branch" {
            if arguments.contains("-D") {
                return GitCommandDescriptor(effect: .destructive, presentation: nil)
            }
            let presentation: GitCommandPresentation? = branchArgumentsAreReadOnly(arguments) ? .branchList : nil
            return GitCommandDescriptor(effect: presentation == nil ? .mutating : .readOnly, presentation: presentation)
        }
        if readOnlySubcommands.contains(subcommand) {
            return GitCommandDescriptor(effect: .readOnly, presentation: presentation(for: arguments))
        }
        if interactiveSubcommands.contains(subcommand) {
            return GitCommandDescriptor(effect: .interactive, presentation: nil)
        }
        if destructiveSubcommands.contains(subcommand) {
            return GitCommandDescriptor(effect: .destructive, presentation: nil)
        }
        return GitCommandDescriptor(effect: .mutating, presentation: nil)
    }

    private static let readOnlySubcommands: Set<String> = [
        "blame", "diff", "log", "show", "status", "tag",
    ]

    private static let interactiveSubcommands: Set<String> = [
        "bisect", "citool", "gui", "help", "mergetool",
    ]

    private static let destructiveSubcommands: Set<String> = [
        "clean", "reset",
    ]

    private static func presentation(for arguments: [String]) -> GitCommandPresentation? {
        guard let subcommand = arguments.first else { return nil }
        switch subcommand {
        case "branch":
            return branchArgumentsAreReadOnly(arguments) ? .branchList : nil
        case "log":
            return .commitLog
        case "status":
            return .statusList
        case "stash":
            return arguments.dropFirst().first == "list" ? .plainOutput : nil
        case "diff":
            return arguments.contains("--stat") ? .plainOutput : nil
        case "show",
             "tag",
             "blame":
            return .plainOutput
        default:
            return nil
        }
    }

    private static func branchArgumentsAreReadOnly(_ arguments: [String]) -> Bool {
        if arguments.count == 1 {
            return true
        }
        let flags = Set(arguments.dropFirst().filter { $0.hasPrefix("-") })
        let allowed: Set = ["--list", "-l", "-a", "-r", "--all", "--remotes", "--format=%(refname:short)"]
        if !flags.isSubset(of: allowed) {
            return false
        }
        return flags.contains("--list") || flags.contains("-l") || arguments.dropFirst().allSatisfy { $0.hasPrefix("-") }
    }
}
