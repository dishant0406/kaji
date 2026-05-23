import SwiftUI

enum KajiSelectVariant {
    case filled
    case plain
}

struct KajiSelectOption<Value: Hashable>: Identifiable {
    let id: String
    let title: String
    let value: Value
}

struct KajiSelect<Value: Hashable>: View {
    let options: [KajiSelectOption<Value>]
    @Binding var selection: Value
    var placeholder: String?
    var width: CGFloat?
    var variant: KajiSelectVariant = .filled
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .kajiFont(size: 12)
                    .foregroundStyle(selectedOption == nil ? KajiTheme.fgDim : KajiTheme.fg)
                    .lineLimit(1)

                Spacer(minLength: 0)

                KajiIcon(systemName: "chevron.up.chevron.down", size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
            .background(controlBackground, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .stroke(controlBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .kajiPointer()
        .kajiPopover(isPresented: $isPresented, preferredEdge: .top) {
            popoverContent
        }
        .accessibilityRepresentation {
            Picker(selection: $selection, label: EmptyView()) {
                ForEach(options) { option in
                    Text(option.title).tag(option.value)
                }
            }
        }
    }

    private var popoverContent: some View {
        SearchableListPicker(
            items: pickerItems,
            filterKey: \.title,
            placeholder: placeholder ?? "Search",
            emptyLabel: "No options",
            emptyActionTitle: nil,
            emptyActionDetail: nil,
            onEmptyAction: nil,
            onSelect: { item in
                selection = item.value
                isPresented = false
            },
            row: { item, isHighlighted in
                KajiSelectRow(
                    title: item.title,
                    isSelected: item.value == selection,
                    isHighlighted: isHighlighted
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
            }
        )
        .frame(width: max(width ?? 220, 220), height: min(CGFloat(options.count) * 40 + 54, 280))
    }

    private var pickerItems: [KajiSelectItem<Value>] {
        options.map { KajiSelectItem(id: $0.id, title: $0.title, value: $0.value) }
    }

    private var controlBackground: Color {
        if variant == .plain { return .clear }
        return transparencyEnabled ? KajiTheme.surface.opacity(0.5) : KajiTheme.surface
    }

    private var controlBorder: Color {
        if variant == .plain { return isPresented ? KajiTheme.border.opacity(0.7) : .clear }
        return isPresented ? KajiTheme.accent.opacity(0.6) : KajiTheme.border
    }
}

private struct KajiSelectItem<Value: Hashable>: Identifiable {
    let id: String
    let title: String
    let value: Value
}

private struct KajiSelectRow: View {
    let title: String
    let isSelected: Bool
    let isHighlighted: Bool
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .kajiFont(size: 12, weight: isSelected ? .medium : .regular)
                .foregroundStyle(KajiTheme.fg)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isSelected {
                KajiIcon(systemName: "checkmark", size: 10)
                    .foregroundStyle(KajiTheme.accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .onHover { hovered = $0 }
        .kajiPointer()
    }

    private var rowBackground: Color {
        if isSelected { return transparencyEnabled ? KajiTheme.accentSoft.opacity(0.7) : KajiTheme.accentSoft }
        if isHighlighted { return transparencyEnabled ? KajiTheme.surface.opacity(0.44) : KajiTheme.surface }
        if hovered { return transparencyEnabled ? KajiTheme.hover.opacity(0.5) : KajiTheme.hover }
        return .clear
    }
}

extension KajiSelect {
    private var selectedOption: KajiSelectOption<Value>? {
        options.first { $0.value == selection }
    }

    private var selectedTitle: String {
        selectedOption?.title ?? placeholder ?? ""
    }
}
