import SwiftUI

struct AIGatewayLogsSection: View {
    let logs: [String]

    var body: some View {
        SettingsSection("Gateway Logs", footer: nil, showsDivider: false) {
            VStack(alignment: .leading, spacing: 4) {
                if logs.isEmpty {
                    Text("No gateway logs yet.")
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(KajiTheme.fgDim)
                } else {
                    ForEach(logs.suffix(8), id: \.self) { line in
                        Text(line)
                            .kajiFont(size: SettingsMetrics.footnoteFontSize, design: .monospaced)
                            .foregroundStyle(KajiTheme.fgMuted)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
        }
    }
}
