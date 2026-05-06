import SwiftUI

struct AgentInstructionsButton: View {
    let selected: Bool
    let action: () -> Void

    var body: some View {
        IconButton(
            symbol: "doc.text.magnifyingglass",
            size: 13,
            selected: selected,
            accessibilityLabel: "Agent Instructions"
        ) {
            action()
        }
    }
}
