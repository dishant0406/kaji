import SwiftUI

struct PopoverFooterAction: Identifiable {
    let id: String
    let title: String
    let icon: String?
    let isBusy: Bool
    let action: () -> Void

    init(
        id: String? = nil,
        title: String,
        icon: String? = nil,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id ?? "\(title)|\(icon ?? "")"
        self.title = title
        self.icon = icon
        self.isBusy = isBusy
        self.action = action
    }
}

struct PopoverPicker<Item: Identifiable, RowContent: View>: View {
    let items: [Item]
    let filterKey: (Item) -> String
    let searchPlaceholder: String
    let emptyLabel: String
    let emptyActionTitle: ((String) -> String?)?
    let emptyActionDetail: String?
    let footerActions: [PopoverFooterAction]
    let width: CGFloat
    let height: CGFloat
    let onEmptyAction: ((String) -> Void)?
    let onSelect: (Item) -> Void
    @ViewBuilder let row: (Item, Bool) -> RowContent

    init(
        items: [Item],
        filterKey: @escaping (Item) -> String,
        searchPlaceholder: String,
        emptyLabel: String,
        emptyActionTitle: ((String) -> String?)? = nil,
        emptyActionDetail: String? = nil,
        footerActions: [PopoverFooterAction] = [],
        width: CGFloat = 300,
        height: CGFloat = 420,
        onEmptyAction: ((String) -> Void)? = nil,
        onSelect: @escaping (Item) -> Void,
        @ViewBuilder row: @escaping (Item, Bool) -> RowContent
    ) {
        self.items = items
        self.filterKey = filterKey
        self.searchPlaceholder = searchPlaceholder
        self.emptyLabel = emptyLabel
        self.emptyActionTitle = emptyActionTitle
        self.emptyActionDetail = emptyActionDetail
        self.footerActions = footerActions
        self.width = width
        self.height = height
        self.onEmptyAction = onEmptyAction
        self.onSelect = onSelect
        self.row = row
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchableListPicker(
                items: items,
                filterKey: filterKey,
                placeholder: searchPlaceholder,
                emptyLabel: emptyLabel,
                emptyActionTitle: emptyActionTitle,
                emptyActionDetail: emptyActionDetail,
                onEmptyAction: onEmptyAction,
                onSelect: onSelect,
                row: row
            )
            if !footerActions.isEmpty {
                Divider().overlay(KajiTheme.border.opacity(0.55))
                VStack(spacing: 0) {
                    ForEach(footerActions) { footerAction in
                        footerButton(
                            title: footerAction.title,
                            icon: footerAction.icon,
                            isBusy: footerAction.isBusy,
                            action: footerAction.action
                        )
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .background(
            TranslucentSurface(
                base: KajiTheme.tertiaryBackground,
                material: .menu,
                tintOpacity: 0.74
            )
        )
    }

    private func footerButton(
        title: String,
        icon: String?,
        isBusy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    KajiIcon(systemName: icon, size: 12)
                }
                Text(title)
                    .kajiFont(size: 12, weight: .medium)
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
                    .opacity(isBusy ? 1 : 0)
            }
            .foregroundStyle(KajiTheme.fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}
