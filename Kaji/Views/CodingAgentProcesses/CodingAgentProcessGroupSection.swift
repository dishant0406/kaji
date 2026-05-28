import SwiftUI

struct CodingAgentProcessGroupSection: View {
    let group: CodingAgentProcessProviderGroup
    let killingPIDs: Set<Int32>
    let onKill: (CodingAgentProcessMatch) -> Void
    let onKillGroup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(group.processes) { match in
                CodingAgentProcessRow(
                    match: match,
                    isKilling: killingPIDs.contains(match.process.pid),
                    onKill: { onKill(match) }
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ProviderIconView(iconName: group.iconName, size: 14, style: .monochrome(KajiTheme.fgMuted))
            Text(group.providerName)
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            KajiBadge(text: "\(group.processes.count)", variant: group.orphanCount > 0 ? .danger : .neutral)
            Spacer(minLength: 8)
            Text(ResourceMonitorFormatting.memory(group.memoryBytes))
                .kajiFont(size: 10, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)
            Button(action: onKillGroup) {
                Text("Kill All")
            }
            .buttonStyle(KajiButtonStyle(.danger, size: .small))
            .disabled(group.processes.allSatisfy { killingPIDs.contains($0.process.pid) })
        }
        .padding(.horizontal, 2)
    }
}
