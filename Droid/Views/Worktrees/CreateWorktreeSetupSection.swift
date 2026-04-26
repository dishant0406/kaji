import SwiftUI

struct CreateWorktreeSetupSection: View {
    let projectPath: String
    let setupCommands: [String]
    @Binding var runSetup: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(setupCommands.isEmpty
                ? "Add .droid/worktree.json to run trusted setup commands after creation."
                : "This repository defines setup commands for new worktrees."
            )
            .droidFont(size: 11)
            .foregroundStyle(DroidTheme.fgDim)

            if setupCommands.isEmpty {
                Text("\(projectPath)/.droid/worktree.json")
                    .droidFont(size: 11, design: .monospaced)
                    .foregroundStyle(DroidTheme.fgMuted)
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(setupCommands, id: \.self) { command in
                        Text(command)
                            .droidFont(size: 11, design: .monospaced)
                            .foregroundStyle(DroidTheme.fg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(DroidTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                        .stroke(DroidTheme.border, lineWidth: 1)
                )

                HStack {
                    Text("Run setup after creation")
                        .droidFont(size: 12)
                        .foregroundStyle(DroidTheme.fg)
                    Spacer()
                    DroidSwitch(isOn: $runSetup)
                }
            }
        }
    }
}
