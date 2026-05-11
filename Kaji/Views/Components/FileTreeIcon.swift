import SwiftUI

struct FileTreeIconButton: View {
    let action: () -> Void

    var body: some View {
        IconButton(
            symbol: "folder",
            size: 13,
            accessibilityLabel: "File Tree"
        ) {
            action()
        }
    }
}
