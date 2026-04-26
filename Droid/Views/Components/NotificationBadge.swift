import SwiftUI

struct NotificationBadge: View {
    let count: Int

    var body: some View {
        Circle()
            .fill(DroidTheme.accent)
            .frame(width: 8, height: 8)
            .accessibilityLabel("\(count) unread notification\(count == 1 ? "" : "s")")
    }
}
