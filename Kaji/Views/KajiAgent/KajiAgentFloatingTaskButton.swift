import SwiftUI

struct KajiAgentFloatingTaskButton: View {
    let state: KajiAgentFloatingTaskState
    @State private var showPopover = false
    @State private var hovered = false

    var body: some View {
        if state.hasVisibleWork {
            Button { showPopover.toggle() } label: {
                HStack(spacing: 8) {
                    KajiIcon(systemName: state.icon, size: 13)
                        .foregroundStyle(iconColor)
                    if state.isWorking {
                        KajiSpinner(size: 10, color: KajiTheme.accent)
                    }
                    if state.badgeCount > 0 {
                        Text("\(state.badgeCount)")
                            .kajiFont(size: 12, weight: .semibold, design: .monospaced)
                            .foregroundStyle(iconColor)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(active ? KajiTheme.surface : KajiTheme.secondaryBackground.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: KajiShape.panelRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: KajiShape.panelRadius)
                        .strokeBorder(KajiTheme.border.opacity(active ? 0.95 : 0.62), lineWidth: 1)
                }
                .overlay {
                    if state.isWorking {
                        SidebarActivityBorder(cornerRadius: KajiShape.panelRadius, lineWidth: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: KajiShape.panelRadius))
            }
            .buttonStyle(.borderless)
            .onHover { hovered = $0 }
            .kajiHoverEffect(isActive: active || state.isWorking)
            .kajiChangeFeedback(KajiMotion.selectionFeedback, value: showPopover, isEnabled: showPopover)
            .kajiChangeFeedback(KajiMotion.attentionFeedback, value: state.badgeCount, isEnabled: state.isWorking)
            .kajiPointer()
            .help(state.detail.isEmpty ? state.title : state.detail)
            .accessibilityLabel(state.title)
            .kajiPopover(isPresented: $showPopover, preferredEdge: .top) {
                KajiAgentFloatingTaskPopover(state: state) { showPopover = false }
            }
        }
    }

    private var active: Bool {
        showPopover || hovered
    }

    private var iconColor: Color {
        if state.failedSubagentCount > 0 { return KajiTheme.diffRemoveFg }
        if state.isWorking { return KajiTheme.accent }
        return active ? KajiTheme.fg : KajiTheme.fgMuted
    }
}

struct KajiAgentFloatingTaskPopover: View {
    let state: KajiAgentFloatingTaskState
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    if !state.taskDetails.isEmpty {
                        subagentSection
                    }
                    if !state.todoPhases.isEmpty {
                        KajiAgentTodoPanel(phases: state.todoPhases)
                    }
                    if state.taskDetails.isEmpty, state.todoPhases.isEmpty {
                        emptyState
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 420)
        }
        .padding(12)
        .frame(width: 400, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: state.icon, size: 12)
                .foregroundStyle(state.isWorking ? KajiTheme.accent : KajiTheme.fgMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tasks & Agents")
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                if !state.detail.isEmpty {
                    Text(state.detail)
                        .kajiFont(size: 11)
                        .foregroundStyle(KajiTheme.fgDim)
                }
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                KajiIcon(systemName: "xmark", size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .accessibilityLabel("Close tasks popover")
        }
    }

    private var subagentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(state.taskDetails.enumerated()), id: \.offset) { _, details in
                KajiAgentSubagentListView(layout: KajiAgentSubagentInlineLayout(details: details))
                    .padding(10)
                    .background(KajiTheme.secondaryBackground.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(KajiTheme.border.opacity(0.45)))
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: "checkmark.circle", size: 12)
                .foregroundStyle(KajiTheme.fgDim)
            Text("No active tasks")
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(KajiTheme.secondaryBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    }
}
