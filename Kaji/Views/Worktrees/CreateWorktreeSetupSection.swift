import SwiftUI

struct CreateWorktreeSetupSection: View {
    let projectPath: String
    let setupCommands: [String]
    @Binding var runSetup: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(setupCommands.isEmpty
                ? "Add .kaji/worktree.json to run trusted setup commands after creation."
                : "This repository defines setup commands for new worktrees."
            )
            .kajiFont(size: 11)
            .foregroundStyle(KajiTheme.fgDim)

            if setupCommands.isEmpty {
                Text("\(projectPath)/.kaji/worktree.json")
                    .kajiFont(size: 11, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(setupCommands, id: \.self) { command in
                        Text(command)
                            .kajiFont(size: 11, design: .monospaced)
                            .foregroundStyle(KajiTheme.fg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(KajiTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                        .stroke(KajiTheme.border, lineWidth: 1)
                )

                HStack {
                    Text("Run setup after creation")
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fg)
                    Spacer()
                    KajiSwitch(isOn: $runSetup)
                }
            }
        }
    }
}
