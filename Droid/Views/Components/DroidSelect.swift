import SwiftUI

struct DroidSelectOption<Value: Hashable>: Identifiable {
    let id: String
    let title: String
    let value: Value
}

struct DroidSelect<Value: Hashable>: View {
    let options: [DroidSelectOption<Value>]
    @Binding var selection: Value
    var placeholder: String?
    var width: CGFloat?
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .droidFont(size: 12)
                    .foregroundStyle(selectedOption == nil ? DroidTheme.fgDim : DroidTheme.fg)
                    .lineLimit(1)

                Spacer(minLength: 0)

                DroidIcon(systemName: "chevron.up.chevron.down", size: 10)
                    .foregroundStyle(DroidTheme.fgDim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
            .background(controlBackground, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .stroke(isPresented ? DroidTheme.accent.opacity(0.6) : DroidTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .droidPopover(isPresented: $isPresented, preferredEdge: .top) {
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
            onSelect: { item in
                selection = item.value
                isPresented = false
            },
            row: { item, isHighlighted in
                DroidSelectRow(
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

    private var pickerItems: [DroidSelectItem<Value>] {
        options.map { DroidSelectItem(id: $0.id, title: $0.title, value: $0.value) }
    }

    private var controlBackground: Color {
        transparencyEnabled ? DroidTheme.surface.opacity(0.5) : DroidTheme.surface
    }
}

private struct DroidSelectItem<Value: Hashable>: Identifiable {
    let id: String
    let title: String
    let value: Value
}

private struct DroidSelectRow: View {
    let title: String
    let isSelected: Bool
    let isHighlighted: Bool
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .droidFont(size: 12, weight: isSelected ? .medium : .regular)
                .foregroundStyle(DroidTheme.fg)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isSelected {
                DroidIcon(systemName: "checkmark", size: 10)
                    .foregroundStyle(DroidTheme.accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        .onHover { hovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return transparencyEnabled ? DroidTheme.accentSoft.opacity(0.7) : DroidTheme.accentSoft }
        if isHighlighted { return transparencyEnabled ? DroidTheme.surface.opacity(0.44) : DroidTheme.surface }
        if hovered { return transparencyEnabled ? DroidTheme.hover.opacity(0.5) : DroidTheme.hover }
        return .clear
    }
}

extension DroidSelect {
    private var selectedOption: DroidSelectOption<Value>? {
        options.first { $0.value == selection }
    }

    private var selectedTitle: String {
        selectedOption?.title ?? placeholder ?? ""
    }
}
