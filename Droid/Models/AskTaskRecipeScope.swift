import Foundation

enum AskTaskRecipeScope: String, CaseIterable, Identifiable {
    case global = "Global"
    case project = "Project"

    var id: String { rawValue }
}
