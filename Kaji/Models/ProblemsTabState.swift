import Foundation

@MainActor
@Observable
final class ProblemsTabState {
    let projectPath: String

    init(projectPath: String) {
        self.projectPath = projectPath
    }
}
