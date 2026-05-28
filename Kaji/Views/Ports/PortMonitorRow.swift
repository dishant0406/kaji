import SwiftUI

struct PortMonitorRow: View {
    let snapshot: PortProcessSnapshot
    let isKilling: Bool
    let onKill: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            KajiBadge(text: ":\(snapshot.port)", variant: .accent)
                .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.processName)
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                Text(detail)
                    .kajiFont(size: 10, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onKill) {
                HStack(spacing: 5) {
                    if isKilling {
                        KajiSpinner(size: 10, lineWidth: 1.4)
                    } else {
                        KajiIcon(systemName: "xmark", size: 9)
                    }
                    Text(isKilling ? "Killing" : "Kill")
                }
            }
            .buttonStyle(KajiButtonStyle(.danger, size: .small))
            .disabled(isKilling)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                .strokeBorder(KajiTheme.border.opacity(0.75), lineWidth: 1)
        )
    }

    private var detail: String {
        "pid \(snapshot.pid)  \(snapshot.protocolName)  \(snapshot.address)"
    }
}
