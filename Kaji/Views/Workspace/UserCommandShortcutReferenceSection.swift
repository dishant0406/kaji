import SwiftUI

struct UserCommandShortcutReferenceSection: View {
    let shortcuts: [UserCommandShortcut]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("User Commands")
                .kajiFont(size: 10, weight: .semibold)
                .foregroundStyle(KajiTheme.fgDim)
                .textCase(.uppercase)
            ForEach(shortcuts) { shortcut in
                HStack(spacing: 10) {
                    ShortcutBadge(label: "::\(shortcut.slug)", compact: true)
                        .frame(width: 82, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shortcut.name)
                            .kajiFont(size: 11)
                            .foregroundStyle(KajiTheme.fgMuted)
                            .lineLimit(1)
                        Text(shortcut.command)
                            .kajiFont(size: 10, design: .monospaced)
                            .foregroundStyle(KajiTheme.fgDim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
