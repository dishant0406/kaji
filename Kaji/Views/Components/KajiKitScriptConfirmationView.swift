import SwiftUI

struct KajiKitScriptConfirmationView: View {
    let script: KajiKitScript
    let onRun: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Run \(script.title)?")
                    .kajiFont(size: 13, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(KajiTheme.fgDim)
                Button("Run", action: onRun)
                    .buttonStyle(.plain)
                    .foregroundStyle(KajiTheme.fg)
            }
            Text(script.command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(KajiTheme.fgMuted)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
                .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border, lineWidth: 1))
        }
        .padding(14)
        .kajiChangeFeedback(KajiMotion.attentionFeedback, value: script.id)
    }
}
