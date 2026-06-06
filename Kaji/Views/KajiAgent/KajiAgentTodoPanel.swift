import SwiftUI

struct KajiAgentTodoPanel: View {
    let phases: [KajiAgentTodoPhase]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                KajiIcon(systemName: "checklist", size: 12)
                    .foregroundStyle(KajiTheme.fgMuted)
                Text("Todos")
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Spacer(minLength: 0)
                Text("\(openCount) open")
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            ForEach(phases) { phase in
                VStack(alignment: .leading, spacing: 5) {
                    if phases.count > 1 {
                        Text(phase.name)
                            .kajiFont(size: 11, weight: .medium)
                            .foregroundStyle(KajiTheme.fgMuted)
                    }
                    ForEach(phase.tasks.prefix(6)) { task in
                        HStack(alignment: .top, spacing: 8) {
                            KajiIcon(systemName: icon(for: task.status), size: 10)
                                .foregroundStyle(color(for: task.status))
                                .frame(width: 14, height: 16)
                            Text(task.content)
                                .kajiFont(size: 11)
                                .foregroundStyle(task.status == "completed" ? KajiTheme.fgDim : KajiTheme.fgMuted)
                                .strikethrough(task.status == "completed")
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 760, alignment: .leading)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var openCount: Int {
        phases.flatMap(\.tasks).count(where: { $0.status != "completed" && $0.status != "abandoned" })
    }

    private func icon(for status: String) -> String {
        switch status {
        case "completed": "checkmark.circle.fill"
        case "in_progress": "arrow.right.circle.fill"
        case "abandoned": "xmark.circle"
        default: "circle"
        }
    }

    private func color(for status: String) -> Color {
        switch status {
        case "completed": KajiTheme.diffAddFg
        case "in_progress": KajiTheme.accent
        case "abandoned": KajiTheme.diffRemoveFg
        default: KajiTheme.fgDim
        }
    }
}
