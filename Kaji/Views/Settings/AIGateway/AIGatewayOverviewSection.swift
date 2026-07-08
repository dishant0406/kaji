import SwiftUI

struct AIGatewayOverviewSection: View {
    let plan: AIGatewaySetupPlan
    let status: AIGatewayRuntimeStatus
    let endpoint: String
    let message: String?
    let isWorking: Bool
    let onPrimary: () -> Void
    let onStop: () -> Void

    var body: some View {
        SettingsSection("AI Gateway", footer: footer) {
            HStack(alignment: .center, spacing: 10) {
                KajiIcon(systemName: "point.3.connected.trianglepath.dotted", size: 16)
                    .frame(width: 18)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.title)
                        .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                    Text(message ?? plan.detail)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if running {
                    Button("Stop", action: onStop)
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                        .disabled(isWorking)
                }
                Button(plan.primaryTitle, action: onPrimary)
                    .buttonStyle(KajiButtonStyle(.primary, size: .small))
                    .disabled(!plan.canRunPrimary || isWorking)
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
        }
    }

    private var running: Bool {
        if case .running = status { return true }
        return false
    }

    private var statusColor: Color {
        if case .failed = status { return KajiTheme.diffRemoveFg }
        return running ? KajiTheme.diffAddFg : KajiTheme.fgDim
    }

    private var footer: String {
        "Local endpoint: \(endpoint). Provider keys stay on this Mac."
    }
}
