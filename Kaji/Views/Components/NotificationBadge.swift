import SwiftUI

struct NotificationBadge: View {
    let count: Int

    var body: some View {
        Circle()
            .fill(KajiTheme.accent)
            .frame(width: 8, height: 8)
            .kajiChangeFeedback(KajiMotion.attentionFeedback, value: count, isEnabled: count > 0)
            .accessibilityLabel("\(count) unread notification\(count == 1 ? "" : "s")")
    }
}
