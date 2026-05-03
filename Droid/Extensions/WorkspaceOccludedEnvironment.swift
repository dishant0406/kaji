import SwiftUI

private struct WorkspaceOccludedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var workspaceOccluded: Bool {
        get { self[WorkspaceOccludedKey.self] }
        set { self[WorkspaceOccludedKey.self] = newValue }
    }
}
