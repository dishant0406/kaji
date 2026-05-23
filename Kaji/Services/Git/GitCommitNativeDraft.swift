import Foundation

enum GitCommitNativeDraft {
    static func message(for inventory: GitCommitInventory) -> String {
        guard !inventory.files.isEmpty else { return "" }
        let verb = leadingVerb(files: inventory.files)
        let scope = leadingScope(inventory)
        return "\(verb) \(scope)"
    }

    static func summary(for inventory: GitCommitInventory) -> String {
        let fileText = "\(inventory.fileCount) file\(inventory.fileCount == 1 ? "" : "s")"
        let statText = "+\(inventory.totalAdditions) -\(inventory.totalDeletions)"
        let groups = inventory.directoryGroups.prefix(3).map(\.path).joined(separator: ", ")
        guard !groups.isEmpty else { return "\(fileText) changed, \(statText)" }
        return "\(fileText) changed, \(statText) in \(groups)"
    }

    private static func leadingVerb(files: [GitCommitInventoryFile]) -> String {
        let added = files.count(where: { $0.status == "A" || $0.status == "U" })
        let deleted = files.count(where: { $0.status == "D" })
        let modified = files.count - added - deleted
        if added > 0, modified == 0, deleted == 0 { return "Add" }
        if deleted > 0, modified == 0, added == 0 { return "Remove" }
        if added > modified, deleted == 0 { return "Add" }
        return "Update"
    }

    private static func leadingScope(_ inventory: GitCommitInventory) -> String {
        if inventory.files.count == 1 {
            return readablePath(inventory.files[0].path)
        }
        guard let group = inventory.directoryGroups.first else {
            return "project changes"
        }
        if group.fileCount == inventory.files.count {
            return readablePath(group.path)
        }
        return "\(readablePath(group.path)) and related changes"
    }

    private static func readablePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "./"))
        guard !trimmed.isEmpty else { return "project changes" }
        return trimmed.replacingOccurrences(of: "/", with: " ")
    }
}
