import SwiftUI

struct DevelopmentBadge: View {
    var body: some View {
        Text("DEV")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(DroidTheme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.badgeRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DroidShape.badgeRadius)
                    .strokeBorder(DroidTheme.border, lineWidth: 1)
            }
            .allowsHitTesting(false)
    }
}
