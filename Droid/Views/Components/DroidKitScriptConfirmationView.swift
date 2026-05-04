import SwiftUI

struct DroidKitScriptConfirmationView: View {
    let script: DroidKitScript
    let onRun: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Run \(script.title)?")
                    .droidFont(size: 13, weight: .semibold)
                    .foregroundStyle(DroidTheme.fg)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(DroidTheme.fgDim)
                Button("Run", action: onRun)
                    .buttonStyle(.plain)
                    .foregroundStyle(DroidTheme.fg)
            }
            Text(script.command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DroidTheme.fgMuted)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(DroidTheme.surface, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
                .overlay(RoundedRectangle(cornerRadius: DroidShape.tileRadius).stroke(DroidTheme.border, lineWidth: 1))
        }
        .padding(14)
    }
}
