import Foundation

struct DiffPaletteFile: Hashable {
    let projectID: UUID
    let worktreeID: UUID
    let worktreePath: String
    let file: GitStatusFile
    let isStaged: Bool

    var id: String {
        "\(projectID.uuidString):\(worktreeID.uuidString):\(isStaged ? "staged" : "changes"):\(file.path)"
    }

    var sectionTitle: String {
        isStaged ? "Staged" : "Changes"
    }
}
