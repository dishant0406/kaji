import SwiftUI

struct CreateWorktreeErrorSection: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            Text(message)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.diffRemoveFg)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
    }
}
