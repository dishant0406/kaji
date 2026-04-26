import SwiftUI

struct BranchPicker: View {
    let currentBranch: String?
    let branches: [String]
    let isLoading: Bool
    let onSelect: (String) -> Void
    let onRefresh: () -> Void
    let onCreateBranch: (() -> Void)?
    let onDeleteBranch: ((String) -> Void)?
    @State private var showPopover = false

    private var branchItems: [BranchItem] {
        branches.map { BranchItem(name: $0) }
    }

    var body: some View {
        Button {
            onRefresh()
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                DroidIcon(systemName: "arrow.triangle.branch", size: 9)
                Text(currentBranch ?? "detached")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120, alignment: .leading)
                DroidIcon(systemName: "chevron.down", size: 8)
                    .foregroundStyle(DroidTheme.fgDim)
            }
            .foregroundStyle(DroidTheme.fg.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(DroidTheme.surface, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(currentBranch ?? "detached")
        .accessibilityLabel("Branch: \(currentBranch ?? "detached")")
        .accessibilityHint("Opens branch picker")
        .droidPopover(isPresented: $showPopover, preferredEdge: .top) {
            PopoverPicker(
                items: branchItems,
                filterKey: \.name,
                searchPlaceholder: "Search branches…",
                emptyLabel: isLoading ? "Loading…" : "No branches found",
                footerActions: onCreateBranch.map { action in
                    [
                        PopoverFooterAction(
                            title: "New Branch…",
                            icon: "plus.square.dashed",
                            action: {
                                showPopover = false
                                action()
                            }
                        ),
                    ]
                } ?? [],
                onSelect: { item in
                    showPopover = false
                    onSelect(item.name)
                },
                row: { item, isHighlighted in
                    BranchRow(
                        name: item.name,
                        isActive: item.name == currentBranch,
                        isHighlighted: isHighlighted
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .contextMenu {
                        if let onDeleteBranch, item.name != currentBranch {
                            Button("Delete Branch", role: .destructive) {
                                showPopover = false
                                onDeleteBranch(item.name)
                            }
                        }
                    }
                }
            )
        }
    }
}

private struct BranchItem: Identifiable {
    let name: String
    var id: String { name }
}

private struct BranchRow: View {
    let name: String
    let isActive: Bool
    let isHighlighted: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isActive ? DroidTheme.accent : DroidTheme.fgDim.opacity(0.35))
                .frame(width: 7, height: 7)
                .frame(width: 10)

            Text(name)
                .font(.system(size: 12, weight: isActive ? .semibold : .medium, design: .monospaced))
                .foregroundStyle(isActive ? DroidTheme.fg : DroidTheme.fg.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if isActive {
                DroidIcon(systemName: "checkmark", size: 10)
                    .foregroundStyle(DroidTheme.accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovered = $0 }
    }

    private var rowBackground: AnyShapeStyle {
        if isActive { return AnyShapeStyle(DroidTheme.accentSoft) }
        if isHighlighted { return AnyShapeStyle(DroidTheme.surface) }
        if hovered { return AnyShapeStyle(DroidTheme.hover) }
        return AnyShapeStyle(Color.clear)
    }
}
