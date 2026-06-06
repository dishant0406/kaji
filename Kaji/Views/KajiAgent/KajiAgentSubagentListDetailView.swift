import SwiftUI

struct KajiAgentSubagentListDetailView: View {
    let agents: [KajiAgentSubagentProgress]
    let onClose: () -> Void
    @Environment(KajiModalCoordinator.self) private var modalCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(agents) { agent in
                        KajiAgentSubagentRow(agent: agent) {
                            modalCoordinator.present(.subagent(agent))
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 640, height: 520, alignment: .topLeading)
        .background(KajiTheme.bg, in: RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Subagents")
                .kajiFont(size: 14, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text("\(agents.count)")
                .kajiFont(size: 12, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)
            Spacer(minLength: 0)
            Button(action: onClose) {
                KajiIcon(systemName: "xmark", size: 11)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .kajiPointer()
        }
        .padding(14)
    }
}
