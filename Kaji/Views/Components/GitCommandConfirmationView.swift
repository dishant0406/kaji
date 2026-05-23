import SwiftUI

struct GitCommandConfirmationView: View {
    let request: GitCommandRequest
    let onRun: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                KajiIcon(systemName: "exclamationmark.triangle", size: 14)
                    .foregroundStyle(KajiTheme.diffHunkFg)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Confirm Git Command")
                        .kajiFont(size: 13, weight: .semibold)
                        .foregroundStyle(KajiTheme.fg)
                    Text(request.displayCommand)
                        .kajiFont(size: 12, design: .monospaced)
                        .foregroundStyle(KajiTheme.fgMuted)
                }
            }

            Text(request.confirmationMessage ?? "Run this command?")
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                Button("Run", action: onRun)
                    .buttonStyle(KajiButtonStyle(.primary, size: .small))
            }
        }
        .padding(16)
    }
}
