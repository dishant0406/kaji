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
            HStack(spacing: 6) {
                KajiIcon(systemName: "arrow.triangle.branch", size: 10)
                Text(currentBranch ?? "detached")
                    .kajiFont(size: 11, weight: .medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 140, alignment: .leading)
                KajiIcon(systemName: "chevron.down", size: 8)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            .foregroundStyle(KajiTheme.fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(KajiTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .kajiHoverEffect(isActive: showPopover, scale: 1.01)
        .kajiChangeFeedback(KajiMotion.selectionFeedback, value: currentBranch ?? "detached")
        .help(currentBranch ?? "detached")
        .accessibilityLabel("Branch: \(currentBranch ?? "detached")")
        .accessibilityHint("Opens branch picker")
        .kajiPopover(isPresented: $showPopover, preferredEdge: .top) {
            PopoverPicker(
                items: branchItems,
                filterKey: \.name,
                searchPlaceholder: "Search branches…",
                emptyLabel: isLoading ? "Loading…" : "No branches found",
                footerActions: onCreateBranch.map { action in
                    [
                        PopoverFooterAction(
                            title: "New Branch",
                            icon: "plus",
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
            Text(name)
                .kajiFont(size: 12, weight: isActive ? .semibold : .medium, design: .monospaced)
                .foregroundStyle(isActive ? KajiTheme.fg : KajiTheme.fg.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if isActive {
                KajiIcon(systemName: "checkmark", size: 10)
                    .foregroundStyle(KajiTheme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .onHover { hovered = $0 }
        .animation(KajiMotion.fast, value: isHighlighted)
        .animation(KajiMotion.hover, value: hovered)
        .kajiChangeFeedback(KajiMotion.selectionFeedback, value: isActive, isEnabled: isActive)
    }

    private var rowBackground: AnyShapeStyle {
        if isActive { return AnyShapeStyle(KajiTheme.accentSoft) }
        if isHighlighted { return AnyShapeStyle(KajiTheme.surface) }
        if hovered { return AnyShapeStyle(KajiTheme.hover) }
        return AnyShapeStyle(Color.clear)
    }
}
